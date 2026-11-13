package main

import (
	"encoding/binary"
	"encoding/hex"
	"errors"
	"io"
	"log"
	"net/http"
	"net/netip"
	"strconv"
	"sync/atomic"
	"time"
)

type config struct {
	limits         storeLimits
	rateLimit      int // requests per client per rateWindow
	trustedProxies []netip.Prefix
	now            func() time.Time
	logger         *log.Logger
}

func defaultConfig(logger *log.Logger) config {
	return config{
		limits: storeLimits{
			ttl:                  packetTTL,
			maxPacketsPerMailbox: defaultMaxPacketsPerMailbox,
			maxMailboxBytes:      defaultMaxMailboxBytes,
			maxTotalBytes:        defaultMaxTotalBytes,
		},
		rateLimit: defaultRateLimit,
		now:       time.Now,
		logger:    logger,
	}
}

// counters are the only per-request information the relay keeps: totals,
// with no address, mailbox id or packet attached.
type counters struct {
	stored, fetched, health                  atomic.Int64
	rejectedID, rejectedSize, rejectedEmpty  atomic.Int64
	rejectedRate, rejectedFull, rejectedHead atomic.Int64
	expired, writeErrors, serverErrors       atomic.Int64
}

type relay struct {
	cfg     config
	store   *store
	limiter *rateLimiter
	ips     ipResolver
	log     *log.Logger
	stats   counters
}

func newRelay(cfg config) *relay {
	return &relay{
		cfg:     cfg,
		store:   newStore(cfg.limits),
		limiter: newRateLimiter(cfg.rateLimit, rateWindow),
		ips:     ipResolver{trusted: cfg.trustedProxies},
		log:     cfg.logger,
	}
}

// handler serves exactly three routes. Anything else is 404, or 405 for a
// known path with another method.
func (r *relay) handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/mailbox/{id}", r.handlePost)
	mux.HandleFunc("GET /v1/mailbox/{id}", r.handleGet)
	mux.HandleFunc("GET /healthz", r.handleHealth)
	return r.recoverPanics(mux)
}

// POST /v1/mailbox/{id}: the body is one packet, raw bytes.
func (r *relay) handlePost(w http.ResponseWriter, req *http.Request) {
	if !r.allow(w, req) {
		return
	}
	id, ok := parseMailboxID(req.PathValue("id"))
	if !ok {
		r.stats.rejectedID.Add(1)
		writeError(w, http.StatusBadRequest, "invalid mailbox id")
		return
	}
	if req.ContentLength > maxPacketSize {
		r.stats.rejectedSize.Add(1)
		writeError(w, http.StatusRequestEntityTooLarge, "packet too large")
		return
	}
	body, err := io.ReadAll(http.MaxBytesReader(w, req.Body, maxPacketSize))
	if err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			r.stats.rejectedSize.Add(1)
			writeError(w, http.StatusRequestEntityTooLarge, "packet too large")
			return
		}
		r.stats.writeErrors.Add(1)
		writeError(w, http.StatusBadRequest, "could not read packet")
		return
	}
	if len(body) == 0 {
		r.stats.rejectedEmpty.Add(1)
		writeError(w, http.StatusBadRequest, "empty packet")
		return
	}
	if err := r.store.put(id, body, r.cfg.now()); err != nil {
		r.stats.rejectedFull.Add(1)
		writeError(w, http.StatusInsufficientStorage, err.Error())
		return
	}
	r.stats.stored.Add(1)
	noStore(w)
	w.WriteHeader(http.StatusNoContent)
}

// GET /v1/mailbox/{id}: all stored packets, oldest first, each as a 4-byte
// big-endian length followed by the packet. An unknown mailbox and an empty
// one give the same response: 200 with an empty body.
func (r *relay) handleGet(w http.ResponseWriter, req *http.Request) {
	if req.Method == http.MethodHead {
		// The mux lets HEAD through on GET routes; only GET is offered.
		r.stats.rejectedHead.Add(1)
		w.Header().Set("Allow", http.MethodGet)
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if !r.allow(w, req) {
		return
	}
	id, ok := parseMailboxID(req.PathValue("id"))
	if !ok {
		r.stats.rejectedID.Add(1)
		writeError(w, http.StatusBadRequest, "invalid mailbox id")
		return
	}
	packets := r.store.get(id, r.cfg.now())
	size := 0
	for _, p := range packets {
		size += 4 + len(p)
	}
	h := w.Header()
	noStore(w)
	h.Set("Content-Type", "application/octet-stream")
	h.Set("Content-Length", strconv.Itoa(size))
	w.WriteHeader(http.StatusOK)
	var prefix [4]byte
	for _, p := range packets {
		binary.BigEndian.PutUint32(prefix[:], uint32(len(p)))
		if _, err := w.Write(prefix[:]); err != nil {
			r.stats.writeErrors.Add(1)
			return
		}
		if _, err := w.Write(p); err != nil {
			r.stats.writeErrors.Add(1)
			return
		}
	}
	r.stats.fetched.Add(1)
}

func (r *relay) handleHealth(w http.ResponseWriter, req *http.Request) {
	if req.Method == http.MethodHead {
		w.Header().Set("Allow", http.MethodGet)
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	r.stats.health.Add(1)
	noStore(w)
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	io.WriteString(w, "ok\n")
}

// allow applies the per-client rate limit, before anything else is read.
func (r *relay) allow(w http.ResponseWriter, req *http.Request) bool {
	ok, wait := r.limiter.allow(clientKey(r.ips.clientAddr(req)), r.cfg.now())
	if ok {
		return true
	}
	r.stats.rejectedRate.Add(1)
	secs := int((wait + time.Second - 1) / time.Second)
	if secs < 1 {
		secs = 1
	}
	w.Header().Set("Retry-After", strconv.Itoa(secs))
	writeError(w, http.StatusTooManyRequests, "too many requests")
	return false
}

// recoverPanics answers 500 without letting net/http log the panic, because
// its log line includes the client's address.
func (r *relay) recoverPanics(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		defer func() {
			if v := recover(); v != nil {
				if v == http.ErrAbortHandler {
					panic(v)
				}
				r.stats.serverErrors.Add(1)
				r.log.Print("error: request handler panicked (details suppressed)")
				writeError(w, http.StatusInternalServerError, "internal error")
			}
		}()
		next.ServeHTTP(w, req)
	})
}

// janitor drops expired packets and forgotten rate-limit entries, and logs
// the counters now and then.
func (r *relay) janitor(stop <-chan struct{}) {
	sweep := time.NewTicker(janitorInterval)
	report := time.NewTicker(countersInterval)
	defer sweep.Stop()
	defer report.Stop()
	for {
		select {
		case <-stop:
			return
		case <-sweep.C:
			r.sweep()
		case <-report.C:
			r.logCounters()
		}
	}
}

func (r *relay) sweep() {
	now := r.cfg.now()
	r.stats.expired.Add(int64(r.store.sweep(now)))
	r.limiter.sweep(now)
}

// logCounters writes totals only: no address, mailbox id or packet.
func (r *relay) logCounters() {
	s := r.store.stats()
	c := &r.stats
	r.log.Printf("counters: stored=%d fetched=%d health=%d rejected_id=%d rejected_size=%d "+
		"rejected_empty=%d rejected_rate=%d rejected_full=%d rejected_head=%d expired=%d "+
		"write_errors=%d server_errors=%d mailboxes=%d packets=%d bytes=%d",
		c.stored.Load(), c.fetched.Load(), c.health.Load(), c.rejectedID.Load(),
		c.rejectedSize.Load(), c.rejectedEmpty.Load(), c.rejectedRate.Load(),
		c.rejectedFull.Load(), c.rejectedHead.Load(), c.expired.Load(),
		c.writeErrors.Load(), c.serverErrors.Load(), s.mailboxes, s.packets, s.bytes)
}

// suppressedErrors replaces net/http's own error log, whose lines can contain
// the client's address (for example "http: panic serving <addr>").
type suppressedErrors struct{ r *relay }

func (s suppressedErrors) Write(p []byte) (int, error) {
	s.r.stats.serverErrors.Add(1)
	s.r.log.Print("error: http server error (details suppressed)")
	return len(p), nil
}

// parseMailboxID accepts exactly mailboxIDLen bytes as hex, either case.
func parseMailboxID(s string) (mailboxID, bool) {
	var id mailboxID
	if len(s) != 2*mailboxIDLen {
		return id, false
	}
	if _, err := hex.Decode(id[:], []byte(s)); err != nil {
		return id, false
	}
	return id, true
}

func noStore(w http.ResponseWriter) {
	h := w.Header()
	h.Set("Cache-Control", "no-store")
	h.Set("X-Content-Type-Options", "nosniff")
}

// writeError sends a fixed message. It never echoes the request.
func writeError(w http.ResponseWriter, code int, msg string) {
	noStore(w)
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(code)
	io.WriteString(w, msg+"\n")
}

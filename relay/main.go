// Command relay is SHA's relay server, version 1: it stores opaque packets
// in RAM per mailbox id and hands them out again. See README.md.
package main

import (
	"context"
	"errors"
	"flag"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	logger := log.New(os.Stderr, "relay: ", log.LstdFlags|log.LUTC)
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	if err := run(ctx, os.Args[1:], logger, nil); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return
		}
		logger.Fatal(err)
	}
}

// run starts the relay and serves until ctx is cancelled. ready, if not nil,
// is called with the listening port once the server accepts connections.
// Returned errors never contain an address.
func run(ctx context.Context, args []string, logger *log.Logger, ready func(port string)) error {
	cfg := defaultConfig(logger)
	fs := flag.NewFlagSet("relay", flag.ContinueOnError)
	addr := fs.String("addr", "127.0.0.1:8080", "listen address (keep it local and put a TLS proxy in front)")
	trusted := fs.String("trusted-proxies", "", "comma-separated proxy addresses or CIDRs whose X-Forwarded-For is used; empty = never")
	fs.IntVar(&cfg.rateLimit, "rate-limit", cfg.rateLimit, "requests per client per minute")
	fs.IntVar(&cfg.limits.maxPacketsPerMailbox, "max-packets-per-mailbox", cfg.limits.maxPacketsPerMailbox, "packets per mailbox")
	mailboxMiB := fs.Int64("max-mailbox-mib", cfg.limits.maxMailboxBytes>>20, "MiB per mailbox")
	totalMiB := fs.Int64("max-total-mib", cfg.limits.maxTotalBytes>>20, "MiB for all packets")
	if err := fs.Parse(args); err != nil {
		return err
	}

	proxies, err := parseTrustedProxies(*trusted)
	if err != nil {
		return err
	}
	cfg.trustedProxies = proxies
	cfg.limits.maxMailboxBytes = *mailboxMiB << 20
	cfg.limits.maxTotalBytes = *totalMiB << 20
	if cfg.rateLimit < 1 || cfg.limits.maxPacketsPerMailbox < 1 ||
		cfg.limits.maxMailboxBytes < maxPacketSize || cfg.limits.maxTotalBytes < cfg.limits.maxMailboxBytes {
		return errors.New("config: limits must be positive, max-mailbox-mib must fit one packet and max-total-mib one mailbox")
	}

	r := newRelay(cfg)
	srv := newHTTPServer(r)
	ln, err := net.Listen("tcp", *addr)
	if err != nil {
		// The error text contains the listen address; keep it out of the log.
		return errors.New("listen failed: check -addr (address in use or not allowed)")
	}

	stop := make(chan struct{})
	go r.janitor(stop)
	go func() {
		<-ctx.Done()
		shutdown, done := context.WithTimeout(context.Background(), shutdownTimeout)
		defer done()
		_ = srv.Shutdown(shutdown)
	}()

	// The port only: no address, so the log never holds an IP.
	_, port, _ := net.SplitHostPort(ln.Addr().String())
	logger.Printf("started: port=%s ttl=%s max_packet=%d max_packets_per_mailbox=%d "+
		"max_mailbox_bytes=%d max_total_bytes=%d rate_limit=%d/min trusted_proxies=%d",
		port, cfg.limits.ttl, maxPacketSize, cfg.limits.maxPacketsPerMailbox,
		cfg.limits.maxMailboxBytes, cfg.limits.maxTotalBytes, cfg.rateLimit, len(proxies))
	if ready != nil {
		ready(port)
	}

	err = srv.Serve(ln)
	close(stop)
	r.logCounters()
	logger.Print("stopped: all stored packets are discarded")
	if err != nil && !errors.Is(err, http.ErrServerClosed) {
		return errors.New("serve failed (details suppressed)")
	}
	return nil
}

func newHTTPServer(r *relay) *http.Server {
	return &http.Server{
		Handler:           r.handler(),
		ReadHeaderTimeout: readHeaderTimeout,
		ReadTimeout:       readTimeout,
		WriteTimeout:      writeTimeout,
		IdleTimeout:       idleTimeout,
		MaxHeaderBytes:    maxHeaderBytes,
		ErrorLog:          log.New(suppressedErrors{r}, "", 0),
	}
}

package main

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakeClock lets tests move time forward without sleeping.
type fakeClock struct {
	mu  sync.Mutex
	now time.Time
}

func newFakeClock() *fakeClock {
	return &fakeClock{now: time.Date(2026, 11, 13, 12, 0, 0, 0, time.UTC)}
}

func (c *fakeClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

func (c *fakeClock) Advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.now = c.now.Add(d)
}

type testRelay struct {
	*relay
	clock *fakeClock
	logs  *bytes.Buffer
	h     http.Handler
}

func newTestRelay(t *testing.T, change func(*config)) *testRelay {
	t.Helper()
	logs := &bytes.Buffer{}
	clock := newFakeClock()
	cfg := defaultConfig(log.New(logs, "", 0))
	cfg.now = clock.Now
	if change != nil {
		change(&cfg)
	}
	r := newRelay(cfg)
	return &testRelay{relay: r, clock: clock, logs: logs, h: r.handler()}
}

const (
	idA = "00112233445566778899aabbccddeeff"
	idB = "ffeeddccbbaa99887766554433221100"
)

// do sends one request from the given client address ("" = httptest default).
func (tr *testRelay) do(method, path string, body []byte, from string) *httptest.ResponseRecorder {
	var rd io.Reader
	if body != nil {
		rd = bytes.NewReader(body)
	}
	req := httptest.NewRequest(method, path, rd)
	if from != "" {
		req.RemoteAddr = from
	}
	rec := httptest.NewRecorder()
	tr.h.ServeHTTP(rec, req)
	return rec
}

func (tr *testRelay) post(id string, packet []byte) int {
	return tr.do(http.MethodPost, "/v1/mailbox/"+id, packet, "").Code
}

func (tr *testRelay) fetch(t *testing.T, id string) [][]byte {
	t.Helper()
	rec := tr.do(http.MethodGet, "/v1/mailbox/"+id, nil, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("GET %s: status %d", id, rec.Code)
	}
	return decodeFrames(t, rec.Body.Bytes())
}

// decodeFrames parses the documented GET format: repeated
// [uint32 big-endian length][packet].
func decodeFrames(t *testing.T, b []byte) [][]byte {
	t.Helper()
	var out [][]byte
	for len(b) > 0 {
		if len(b) < 4 {
			t.Fatalf("truncated length prefix")
		}
		n := int(binary.BigEndian.Uint32(b))
		b = b[4:]
		if len(b) < n {
			t.Fatalf("truncated packet")
		}
		out = append(out, b[:n])
		b = b[n:]
	}
	return out
}

func packetOf(size int, fill byte) []byte {
	return bytes.Repeat([]byte{fill}, size)
}

func TestMaxPacketSizeMatchesWireFormat(t *testing.T) {
	// 18 + 65692 + 2 (0004 §5), see limits.go and PacketV3.maxPacketSize.
	if maxPacketSize != 65712 {
		t.Fatalf("maxPacketSize = %d, want 65712", maxPacketSize)
	}
	// The pieces match the size table in 0004 §4 (chain index under 128,
	// so 2 bytes less than the largest).
	if olmMaxNormal-2 != 65585 || olmMaxPreKey-2 != 65692 {
		t.Fatalf("olm sizes %d, %d, want 65587 and 65694", olmMaxNormal, olmMaxPreKey)
	}
}

func TestDropAndFetch(t *testing.T) {
	tr := newTestRelay(t, nil)
	p1, p2 := packetOf(301, 1), packetOf(1069, 2)
	for _, p := range [][]byte{p1, p2} {
		if code := tr.post(idA, p); code != http.StatusNoContent {
			t.Fatalf("POST: status %d", code)
		}
	}
	for round := 0; round < 2; round++ { // fetching does not delete
		got := tr.fetch(t, idA)
		if len(got) != 2 || !bytes.Equal(got[0], p1) || !bytes.Equal(got[1], p2) {
			t.Fatalf("round %d: got %d packets, want p1, p2 in order", round, len(got))
		}
	}
	rec := tr.do(http.MethodGet, "/v1/mailbox/"+idA, nil, "")
	if ct := rec.Header().Get("Content-Type"); ct != "application/octet-stream" {
		t.Errorf("Content-Type = %q", ct)
	}
	if cc := rec.Header().Get("Cache-Control"); cc != "no-store" {
		t.Errorf("Cache-Control = %q", cc)
	}
}

func TestMailboxIDIsCaseInsensitive(t *testing.T) {
	tr := newTestRelay(t, nil)
	tr.post(strings.ToUpper(idA), packetOf(301, 7))
	if got := tr.fetch(t, idA); len(got) != 1 {
		t.Fatalf("got %d packets via lower-case id, want 1", len(got))
	}
}

func TestUnknownAndEmptyMailboxLookTheSame(t *testing.T) {
	tr := newTestRelay(t, nil)
	tr.post(idB, packetOf(301, 3))
	tr.clock.Advance(packetTTL) // idB has existed but is now empty

	unknown := tr.do(http.MethodGet, "/v1/mailbox/"+idA, nil, "")
	emptied := tr.do(http.MethodGet, "/v1/mailbox/"+idB, nil, "")
	if unknown.Code != emptied.Code || unknown.Code != http.StatusOK {
		t.Fatalf("status unknown=%d emptied=%d", unknown.Code, emptied.Code)
	}
	if !bytes.Equal(unknown.Body.Bytes(), emptied.Body.Bytes()) || unknown.Body.Len() != 0 {
		t.Fatalf("bodies differ or are not empty")
	}
	if fmt.Sprint(unknown.Header()) != fmt.Sprint(emptied.Header()) {
		t.Fatalf("headers differ:\n%v\n%v", unknown.Header(), emptied.Header())
	}
}

func TestRejectsBadMailboxIDs(t *testing.T) {
	tr := newTestRelay(t, nil)
	for _, id := range []string{
		idA[:31],                           // too short
		idA + "0",                          // too long
		"zz112233445566778899aabbccddeeff", // not hex
		idA[:30] + "%2F",                   // escaped slash
	} {
		for _, method := range []string{http.MethodPost, http.MethodGet} {
			rec := tr.do(method, "/v1/mailbox/"+id, packetOf(301, 1), "")
			if rec.Code != http.StatusBadRequest && rec.Code != http.StatusNotFound {
				t.Errorf("%s id %q: status %d, want 400 or 404", method, id, rec.Code)
			}
		}
	}
	if tr.store.stats().packets != 0 {
		t.Fatalf("a packet with a bad id was stored")
	}
}

func TestPacketSizeLimits(t *testing.T) {
	tr := newTestRelay(t, nil)
	if code := tr.post(idA, packetOf(maxPacketSize, 1)); code != http.StatusNoContent {
		t.Fatalf("largest packet: status %d, want 204", code)
	}
	if code := tr.post(idA, packetOf(maxPacketSize+1, 1)); code != http.StatusRequestEntityTooLarge {
		t.Fatalf("too large (Content-Length): status %d, want 413", code)
	}
	// Without Content-Length the body limit still applies.
	req := httptest.NewRequest(http.MethodPost, "/v1/mailbox/"+idA,
		io.MultiReader(bytes.NewReader(packetOf(maxPacketSize, 1)), bytes.NewReader([]byte{1})))
	req.ContentLength = -1
	rec := httptest.NewRecorder()
	tr.h.ServeHTTP(rec, req)
	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("too large (chunked): status %d, want 413", rec.Code)
	}
	if code := tr.post(idA, []byte{}); code != http.StatusBadRequest {
		t.Fatalf("empty: status %d, want 400", code)
	}
	if got := tr.fetch(t, idA); len(got) != 1 {
		t.Fatalf("stored %d packets, want only the valid one", len(got))
	}
}

func TestPacketsExpireAfterTTL(t *testing.T) {
	tr := newTestRelay(t, nil)
	tr.post(idA, packetOf(301, 1))
	tr.clock.Advance(packetTTL - time.Nanosecond)
	if got := tr.fetch(t, idA); len(got) != 1 {
		t.Fatalf("just before the TTL: %d packets, want 1", len(got))
	}
	tr.clock.Advance(time.Nanosecond)
	if got := tr.fetch(t, idA); len(got) != 0 {
		t.Fatalf("at the TTL: %d packets, want 0", len(got))
	}
	if s := tr.store.stats(); s != (storeStats{}) {
		t.Fatalf("store not empty after expiry: %+v", s)
	}

	// The janitor's sweep frees memory without anyone fetching.
	tr.post(idB, packetOf(1069, 2))
	tr.clock.Advance(packetTTL)
	tr.sweep()
	if s := tr.store.stats(); s != (storeStats{}) {
		t.Fatalf("store not empty after sweep: %+v", s)
	}
	if n := tr.stats.expired.Load(); n != 1 {
		t.Fatalf("expired counter = %d, want 1", n)
	}
}

func TestCapsRejectNewPacketsAndKeepOldOnes(t *testing.T) {
	t.Run("packets per mailbox", func(t *testing.T) {
		tr := newTestRelay(t, func(c *config) { c.limits.maxPacketsPerMailbox = 3 })
		for i := 0; i < 3; i++ {
			if code := tr.post(idA, packetOf(301, byte(i))); code != http.StatusNoContent {
				t.Fatalf("packet %d: status %d", i, code)
			}
		}
		if code := tr.post(idA, packetOf(301, 9)); code != http.StatusInsufficientStorage {
			t.Fatalf("over the cap: status %d, want 507", code)
		}
		got := tr.fetch(t, idA)
		if len(got) != 3 || got[0][0] != 0 || got[2][0] != 2 {
			t.Fatalf("the first three packets must be kept")
		}
		if code := tr.post(idB, packetOf(301, 9)); code != http.StatusNoContent {
			t.Fatalf("other mailbox: status %d, want 204", code)
		}
	})
	t.Run("bytes per mailbox", func(t *testing.T) {
		tr := newTestRelay(t, func(c *config) { c.limits.maxMailboxBytes = 2 * (4141 + packetOverhead) })
		tr.post(idA, packetOf(4141, 1))
		tr.post(idA, packetOf(4141, 2))
		if code := tr.post(idA, packetOf(301, 3)); code != http.StatusInsufficientStorage {
			t.Fatalf("over the byte cap: status %d, want 507", code)
		}
	})
	t.Run("total memory", func(t *testing.T) {
		tr := newTestRelay(t, func(c *config) {
			c.limits.maxTotalBytes = 2*(16429+packetOverhead) + mailboxOverhead
		})
		tr.post(idA, packetOf(16429, 1))
		tr.post(idA, packetOf(16429, 2))
		if code := tr.post(idB, packetOf(301, 3)); code != http.StatusInsufficientStorage {
			t.Fatalf("store full: status %d, want 507", code)
		}
		if s := tr.store.stats(); s.bytes > tr.cfg.limits.maxTotalBytes {
			t.Fatalf("store holds %d bytes, cap %d", s.bytes, tr.cfg.limits.maxTotalBytes)
		}
		tr.clock.Advance(packetTTL)
		tr.sweep()
		if code := tr.post(idB, packetOf(301, 3)); code != http.StatusNoContent {
			t.Fatalf("after expiry: status %d, want 204", code)
		}
	})
}

func TestRateLimitTripsAndReleases(t *testing.T) {
	tr := newTestRelay(t, func(c *config) { c.rateLimit = 5 })
	const client, other = "198.51.100.7:4000", "198.51.100.8:4000"
	path := "/v1/mailbox/" + idA
	for i := 0; i < 5; i++ {
		if rec := tr.do(http.MethodGet, path, nil, client); rec.Code != http.StatusOK {
			t.Fatalf("request %d: status %d", i, rec.Code)
		}
	}
	rec := tr.do(http.MethodPost, path, packetOf(301, 1), client)
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("over the limit: status %d, want 429", rec.Code)
	}
	if ra := rec.Header().Get("Retry-After"); ra != "60" {
		t.Errorf("Retry-After = %q, want 60", ra)
	}
	if tr.store.stats().packets != 0 {
		t.Fatalf("a rate-limited packet was stored")
	}
	if rec := tr.do(http.MethodGet, path, nil, other); rec.Code != http.StatusOK {
		t.Fatalf("another client: status %d, want 200", rec.Code)
	}

	tr.clock.Advance(rateWindow)
	if rec := tr.do(http.MethodGet, path, nil, client); rec.Code != http.StatusOK {
		t.Fatalf("after the window: status %d, want 200", rec.Code)
	}

	// Addresses are forgotten once their window is over.
	tr.clock.Advance(rateWindow)
	tr.sweep()
	if n := tr.limiter.size(); n != 0 {
		t.Fatalf("rate limiter still holds %d clients", n)
	}
}

func TestRateLimitGroupsIPv6By64(t *testing.T) {
	tr := newTestRelay(t, func(c *config) { c.rateLimit = 2 })
	path := "/v1/mailbox/" + idA
	tr.do(http.MethodGet, path, nil, "[2001:db8:1:2::1]:4000")
	tr.do(http.MethodGet, path, nil, "[2001:db8:1:2::ffff]:4000")
	if rec := tr.do(http.MethodGet, path, nil, "[2001:db8:1:2:aaaa::3]:4000"); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("same /64: status %d, want 429", rec.Code)
	}
	if rec := tr.do(http.MethodGet, path, nil, "[2001:db8:1:3::1]:4000"); rec.Code != http.StatusOK {
		t.Fatalf("other /64: status %d, want 200", rec.Code)
	}
}

func TestOnlyKnownRoutes(t *testing.T) {
	tr := newTestRelay(t, nil)
	cases := []struct {
		method, path string
		want         int
	}{
		{http.MethodGet, "/healthz", http.StatusOK},
		{http.MethodHead, "/healthz", http.StatusMethodNotAllowed},
		{http.MethodHead, "/v1/mailbox/" + idA, http.StatusMethodNotAllowed},
		{http.MethodDelete, "/v1/mailbox/" + idA, http.StatusMethodNotAllowed},
		{http.MethodPut, "/v1/mailbox/" + idA, http.StatusMethodNotAllowed},
		{http.MethodGet, "/v1/mailbox/", http.StatusNotFound},
		{http.MethodGet, "/v1/mailboxes", http.StatusNotFound},
		{http.MethodGet, "/metrics", http.StatusNotFound},
		{http.MethodGet, "/", http.StatusNotFound},
	}
	for _, c := range cases {
		if rec := tr.do(c.method, c.path, nil, ""); rec.Code != c.want {
			t.Errorf("%s %s: status %d, want %d", c.method, c.path, rec.Code, c.want)
		}
	}
}

func TestPanicsAreRecoveredWithoutDetails(t *testing.T) {
	tr := newTestRelay(t, nil)
	h := tr.recoverPanics(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		panic("detail " + idA)
	}))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status %d, want 500", rec.Code)
	}
	if strings.Contains(tr.logs.String(), idA) || strings.Contains(rec.Body.String(), idA) {
		t.Fatalf("panic value leaked")
	}
}

func TestConcurrentDropAndFetch(t *testing.T) {
	tr := newTestRelay(t, func(c *config) { c.rateLimit = 1 << 20 })
	ids := []string{idA, idB, strings.Repeat("ab", mailboxIDLen), strings.Repeat("cd", mailboxIDLen)}
	const writers, perWriter = 16, 50
	var wg sync.WaitGroup
	for w := 0; w < writers; w++ {
		wg.Add(2)
		go func() {
			defer wg.Done()
			for i := 0; i < perWriter; i++ {
				id := ids[(w+i)%len(ids)]
				if code := tr.post(id, packetOf(301, byte(w))); code != http.StatusNoContent {
					t.Errorf("POST: status %d", code)
					return
				}
			}
		}()
		go func() {
			defer wg.Done()
			for i := 0; i < perWriter; i++ {
				rec := tr.do(http.MethodGet, "/v1/mailbox/"+ids[i%len(ids)], nil, "")
				if rec.Code != http.StatusOK {
					t.Errorf("GET: status %d", rec.Code)
					return
				}
				if i%10 == 0 {
					tr.sweep()
				}
			}
		}()
	}
	wg.Wait()
	total := 0
	for _, id := range ids {
		total += len(tr.fetch(t, id))
	}
	if total != writers*perWriter {
		t.Fatalf("stored %d packets, want %d", total, writers*perWriter)
	}
	if s := tr.store.stats(); s.packets != total {
		t.Fatalf("stats say %d packets, want %d", s.packets, total)
	}
}

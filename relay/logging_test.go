package main

import (
	"bytes"
	"context"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

// syncBuffer is a bytes.Buffer safe for the server's goroutines.
type syncBuffer struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (s *syncBuffer) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.Write(p)
}

func (s *syncBuffer) String() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.String()
}

// TestLogsHoldNoAddressesOrMailboxIDs runs the whole program (start,
// requests of every kind, shutdown) and checks every log line it wrote. It
// also makes net/http itself report an error that names the client.
func TestLogsHoldNoAddressesOrMailboxIDs(t *testing.T) {
	logs := &syncBuffer{}
	logger := log.New(logs, "relay: ", log.LstdFlags|log.LUTC)

	const (
		clientV4 = "203.0.113.77"
		clientV6 = "2001:db8::77"
		mailbox  = "0a1b2c3d4e5f60718293a4b5c6d7e8f9"
		marker   = "PACKET-CONTENT-MARKER"
	)
	secrets := []string{clientV4, clientV6, "127.0.0.1", "::1", mailbox, strings.ToUpper(mailbox), marker}

	ctx, cancel := context.WithCancel(context.Background())
	ports := make(chan string, 1)
	done := make(chan error, 1)
	go func() {
		done <- run(ctx, []string{"-addr", "127.0.0.1:0", "-trusted-proxies", "127.0.0.1", "-rate-limit", "8"},
			logger, func(port string) { ports <- port })
	}()
	var port string
	select {
	case port = <-ports:
	case err := <-done:
		t.Fatalf("run: %v", err)
	case <-time.After(10 * time.Second):
		t.Fatal("server did not start")
	}
	base := "http://127.0.0.1:" + port

	send := func(method, path, from string, body []byte) int {
		var rd io.Reader
		if body != nil {
			rd = bytes.NewReader(body)
		}
		req, err := http.NewRequest(method, base+path, rd)
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("X-Forwarded-For", from)
		res, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		io.Copy(io.Discard, res.Body)
		res.Body.Close()
		return res.StatusCode
	}

	packet := append([]byte(marker), make([]byte, 301-len(marker))...)
	path := "/v1/mailbox/" + mailbox
	send(http.MethodPost, path, clientV4, packet)
	send(http.MethodGet, path, clientV4, nil)
	send(http.MethodGet, "/v1/mailbox/"+strings.ToUpper(mailbox), clientV6, nil)
	send(http.MethodPost, "/v1/mailbox/"+mailbox[:20], clientV6, packet) // bad id
	send(http.MethodPost, path, clientV6, make([]byte, maxPacketSize+1)) // too large
	send(http.MethodPost, path, clientV6, []byte{})                      // empty
	send(http.MethodHead, path, clientV6, nil)                           // method
	send(http.MethodGet, "/v1/unknown/"+mailbox, clientV6, nil)          // no route
	send(http.MethodGet, "/healthz", clientV4, nil)
	rateLimited := false
	for i := 0; i < 10; i++ {
		if send(http.MethodGet, path, clientV4, nil) == http.StatusTooManyRequests {
			rateLimited = true
		}
	}
	if !rateLimited {
		t.Fatal("expected the rate limit to trip")
	}

	// net/http logs "http: TLS handshake error from <addr>" through
	// Server.ErrorLog; the relay must swallow the details.
	r := newRelay(defaultConfig(logger))
	tlsServer := httptest.NewUnstartedServer(r.handler())
	tlsServer.Config = newHTTPServer(r)
	tlsServer.StartTLS()
	if res, err := http.Get(strings.Replace(tlsServer.URL, "https://", "http://", 1) + path); err == nil {
		res.Body.Close()
	}
	// Panics are recovered without logging their value.
	r.recoverPanics(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		panic(clientV4 + " " + mailbox)
	})).ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/", nil))
	deadline := time.Now().Add(5 * time.Second)
	for !strings.Contains(logs.String(), "http server error (details suppressed)") && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	tlsServer.Close()

	cancel()
	if err := <-done; err != nil {
		t.Fatalf("run: %v", err)
	}

	out := logs.String()
	for _, want := range []string{"started: port=", "counters: stored=1", "rejected_rate=",
		"http server error (details suppressed)", "request handler panicked", "stopped:"} {
		if !strings.Contains(out, want) {
			t.Errorf("log lacks %q, so the capture is incomplete:\n%s", want, out)
		}
	}
	for _, s := range secrets {
		if strings.Contains(out, s) {
			t.Errorf("log contains %q:\n%s", s, out)
		}
	}
}

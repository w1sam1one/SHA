package main

import (
	"net/http/httptest"
	"net/netip"
	"testing"
)

func TestClientAddr(t *testing.T) {
	proxies, err := parseTrustedProxies("127.0.0.1, 10.0.0.0/8")
	if err != nil {
		t.Fatal(err)
	}
	trusting := ipResolver{trusted: proxies}
	direct := ipResolver{}

	cases := []struct {
		name     string
		resolver ipResolver
		peer     string
		xff      []string
		want     string
	}{
		{"no proxy configured: header ignored", direct, "198.51.100.1:1", []string{"203.0.113.9"}, "198.51.100.1"},
		{"untrusted peer: header ignored", trusting, "198.51.100.1:1", []string{"203.0.113.9"}, "198.51.100.1"},
		{"trusted peer, one hop", trusting, "127.0.0.1:1", []string{"203.0.113.9"}, "203.0.113.9"},
		{"client-written entries on the left are skipped", trusting, "127.0.0.1:1", []string{"6.6.6.6, 203.0.113.9"}, "203.0.113.9"},
		{"several header lines", trusting, "127.0.0.1:1", []string{"6.6.6.6", "203.0.113.9, 10.1.2.3"}, "203.0.113.9"},
		{"only proxies listed: use the peer", trusting, "127.0.0.1:1", []string{"10.1.2.3"}, "127.0.0.1"},
		{"unparseable rightmost hop: use the peer", trusting, "127.0.0.1:1", []string{"203.0.113.9, not-an-ip"}, "127.0.0.1"},
		{"no header: use the peer", trusting, "127.0.0.1:1", nil, "127.0.0.1"},
		{"IPv6 client", trusting, "127.0.0.1:1", []string{"2001:db8::5"}, "2001:db8::5"},
		{"IPv4-mapped peer is unmapped", direct, "[::ffff:198.51.100.1]:1", nil, "198.51.100.1"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			req := httptest.NewRequest("GET", "/healthz", nil)
			req.RemoteAddr = c.peer
			for _, v := range c.xff {
				req.Header.Add("X-Forwarded-For", v)
			}
			if got := c.resolver.clientAddr(req); got != netip.MustParseAddr(c.want) {
				t.Fatalf("got %v, want %s", got, c.want)
			}
		})
	}
}

func TestClientAddrUnknownPeer(t *testing.T) {
	req := httptest.NewRequest("GET", "/healthz", nil)
	req.RemoteAddr = "@"
	if got := (ipResolver{}).clientAddr(req); got.IsValid() {
		t.Fatalf("got %v, want the zero Addr", got)
	}
}

func TestParseTrustedProxies(t *testing.T) {
	got, err := parseTrustedProxies("  ,::1, 192.168.0.0/16 ")
	if err != nil || len(got) != 2 {
		t.Fatalf("got %v, %v", got, err)
	}
	if _, err := parseTrustedProxies("not-an-ip"); err == nil {
		t.Fatal("want an error for an invalid entry")
	} else if err.Error() != "invalid -trusted-proxies entry" {
		t.Fatalf("error must not echo the value: %q", err)
	}
}

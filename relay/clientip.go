package main

import (
	"errors"
	"net/http"
	"net/netip"
	"strings"
)

// ipResolver finds the client address used for the rate limit.
//
// By default it uses the TCP peer address and ignores X-Forwarded-For,
// which any client can set. Only when the peer is one of the trusted
// proxies does it read X-Forwarded-For, from right to left, and take the
// first address that is not itself a trusted proxy: the entries to the left
// of what our own proxy appended are written by the client and cannot be
// trusted. If the relay can be reached without going through the proxy, a
// trusted-proxy setting lets anyone choose their rate-limit key.
type ipResolver struct {
	trusted []netip.Prefix
}

// parseTrustedProxies parses a comma-separated list of IP addresses or CIDR
// prefixes, e.g. "127.0.0.1,::1" or "10.0.0.0/8".
func parseTrustedProxies(list string) ([]netip.Prefix, error) {
	var out []netip.Prefix
	for _, item := range strings.Split(list, ",") {
		item = strings.TrimSpace(item)
		if item == "" {
			continue
		}
		if p, err := netip.ParsePrefix(item); err == nil {
			out = append(out, p.Masked())
			continue
		}
		a, err := netip.ParseAddr(item)
		if err != nil {
			// No value in the message: logs must not hold any address.
			return nil, errors.New("invalid -trusted-proxies entry")
		}
		out = append(out, netip.PrefixFrom(a.Unmap(), a.Unmap().BitLen()))
	}
	return out, nil
}

func (r ipResolver) isTrusted(a netip.Addr) bool {
	for _, p := range r.trusted {
		if p.Contains(a) {
			return true
		}
	}
	return false
}

// clientAddr returns the client's address, or the zero Addr if it cannot be
// determined (all such requests then share one rate-limit key).
func (r ipResolver) clientAddr(req *http.Request) netip.Addr {
	peerPort, err := netip.ParseAddrPort(req.RemoteAddr)
	if err != nil {
		return netip.Addr{}
	}
	peer := peerPort.Addr().Unmap()
	if !r.isTrusted(peer) {
		return peer
	}
	var hops []string
	for _, v := range req.Header.Values("X-Forwarded-For") {
		hops = append(hops, strings.Split(v, ",")...)
	}
	for i := len(hops) - 1; i >= 0; i-- {
		a, ok := parseHop(strings.TrimSpace(hops[i]))
		if !ok {
			// Unparseable: stop here rather than trust anything further left.
			return peer
		}
		if !r.isTrusted(a) {
			return a
		}
	}
	return peer
}

func parseHop(s string) (netip.Addr, bool) {
	if a, err := netip.ParseAddr(s); err == nil {
		return a.Unmap(), true
	}
	if ap, err := netip.ParseAddrPort(s); err == nil {
		return ap.Addr().Unmap(), true
	}
	return netip.Addr{}, false
}

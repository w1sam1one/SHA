package main

import (
	"net/netip"
	"sync"
	"time"
)

// rateLimiter counts requests per client in fixed windows, in RAM only.
// A client's entry is deleted by sweep once its window has ended, so an
// address is held for at most rateWindow + janitorInterval after the first
// request of a window (90 seconds with the defaults). Deleting an entry
// frees it for garbage collection; Go does not overwrite the memory.
type rateLimiter struct {
	limit  int
	window time.Duration

	mu      sync.Mutex
	clients map[netip.Prefix]*windowCount
}

type windowCount struct {
	start time.Time
	count int
}

func newRateLimiter(limit int, window time.Duration) *rateLimiter {
	return &rateLimiter{limit: limit, window: window, clients: make(map[netip.Prefix]*windowCount)}
}

// clientKey groups addresses the way one client typically holds them: a
// single IPv4 address, or a whole IPv6 /64 (one network usually gets a /64
// and can pick any address in it). The zero Prefix stands for "unknown".
func clientKey(addr netip.Addr) netip.Prefix {
	if !addr.IsValid() {
		return netip.Prefix{}
	}
	addr = addr.Unmap()
	if addr.Is4() {
		return netip.PrefixFrom(addr, 32)
	}
	p, err := addr.Prefix(64)
	if err != nil {
		return netip.Prefix{}
	}
	return p
}

// allow records one request and reports whether it is within the limit. If
// not, it also returns how long until the client's window ends.
func (l *rateLimiter) allow(key netip.Prefix, now time.Time) (bool, time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()

	w := l.clients[key]
	if w == nil || !now.Before(w.start.Add(l.window)) {
		w = &windowCount{start: now}
		l.clients[key] = w
	}
	if w.count >= l.limit {
		return false, w.start.Add(l.window).Sub(now)
	}
	w.count++
	return true, 0
}

// sweep forgets every client whose window has ended.
func (l *rateLimiter) sweep(now time.Time) {
	l.mu.Lock()
	defer l.mu.Unlock()
	for key, w := range l.clients {
		if !now.Before(w.start.Add(l.window)) {
			delete(l.clients, key)
		}
	}
}

func (l *rateLimiter) size() int {
	l.mu.Lock()
	defer l.mu.Unlock()
	return len(l.clients)
}

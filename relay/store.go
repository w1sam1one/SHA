package main

import (
	"errors"
	"sync"
	"time"
)

// Bytes counted against the memory caps on top of the packet itself: an
// estimate of the slice header, expiry time and map entry.
const (
	packetOverhead  = 64
	mailboxOverhead = 128
)

var (
	errMailboxFull = errors.New("mailbox full")
	errStoreFull   = errors.New("store full")
)

type mailboxID [mailboxIDLen]byte

type storedPacket struct {
	data    []byte // never modified after it is stored
	expires time.Time
}

type mailbox struct {
	packets []storedPacket // arrival order, so also expiry order
	bytes   int64          // packet bytes + packetOverhead each
}

type storeLimits struct {
	ttl                  time.Duration
	maxPacketsPerMailbox int
	maxMailboxBytes      int64
	maxTotalBytes        int64
}

// store keeps packets in RAM only. Nothing is ever written to disk.
type store struct {
	limits storeLimits

	mu        sync.Mutex
	mailboxes map[mailboxID]*mailbox
	total     int64 // bytes counted against limits.maxTotalBytes
	packets   int
}

func newStore(limits storeLimits) *store {
	return &store{limits: limits, mailboxes: make(map[mailboxID]*mailbox)}
}

// put stores data in the mailbox. When a cap is reached the new packet is
// rejected and the stored ones are kept: dropping old packets instead would
// lose messages without anyone noticing, while a rejected send can be retried.
func (s *store) put(id mailboxID, data []byte, now time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	mb := s.mailboxes[id]
	if mb != nil {
		s.expireLocked(id, mb, now)
		mb = s.mailboxes[id]
	}
	cost := int64(len(data)) + packetOverhead
	newMailbox := int64(0)
	if mb == nil {
		newMailbox = mailboxOverhead
	}
	count, used := 0, int64(0)
	if mb != nil {
		count, used = len(mb.packets), mb.bytes
	}
	if count >= s.limits.maxPacketsPerMailbox || used+cost > s.limits.maxMailboxBytes {
		return errMailboxFull
	}
	if s.total+cost+newMailbox > s.limits.maxTotalBytes {
		return errStoreFull
	}
	if mb == nil {
		mb = &mailbox{}
		s.mailboxes[id] = mb
	}
	mb.packets = append(mb.packets, storedPacket{data: data, expires: now.Add(s.limits.ttl)})
	mb.bytes += cost
	s.total += cost + newMailbox
	s.packets++
	return nil
}

// get returns the mailbox's packets in arrival order. They are not removed:
// they expire after the TTL. An unknown mailbox and an empty one both give nil.
func (s *store) get(id mailboxID, now time.Time) [][]byte {
	s.mu.Lock()
	defer s.mu.Unlock()

	mb := s.mailboxes[id]
	if mb == nil {
		return nil
	}
	s.expireLocked(id, mb, now)
	if s.mailboxes[id] == nil {
		return nil
	}
	out := make([][]byte, len(mb.packets))
	for i, p := range mb.packets {
		out[i] = p.data
	}
	return out
}

// sweep removes every expired packet and empty mailbox. Returns how many
// packets were removed.
func (s *store) sweep(now time.Time) int {
	s.mu.Lock()
	defer s.mu.Unlock()

	removed := 0
	for id, mb := range s.mailboxes {
		removed += s.expireLocked(id, mb, now)
	}
	return removed
}

// expireLocked drops the mailbox's expired packets and deletes it when
// empty. Returns the number of packets dropped.
func (s *store) expireLocked(id mailboxID, mb *mailbox, now time.Time) int {
	n := 0
	for n < len(mb.packets) && !now.Before(mb.packets[n].expires) {
		cost := int64(len(mb.packets[n].data)) + packetOverhead
		mb.bytes -= cost
		s.total -= cost
		n++
	}
	if n > 0 {
		// Shift and clear so the dropped packets can be garbage collected.
		kept := copy(mb.packets, mb.packets[n:])
		clear(mb.packets[kept:])
		mb.packets = mb.packets[:kept]
		s.packets -= n
	}
	if len(mb.packets) == 0 {
		delete(s.mailboxes, id)
		s.total -= mailboxOverhead
	}
	return n
}

type storeStats struct {
	mailboxes int
	packets   int
	bytes     int64
}

func (s *store) stats() storeStats {
	s.mu.Lock()
	defer s.mu.Unlock()
	return storeStats{mailboxes: len(s.mailboxes), packets: s.packets, bytes: s.total}
}

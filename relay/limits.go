package main

import "time"

// Sizes taken from the app's packet format. Keep in sync with:
//
//	lib/crypto/src/wire_format.dart  WireFormat.mailboxIdLength = 16,
//	                                 headerLength = 1 (version) + 16 (mailbox id)
//	lib/crypto/src/aes_gcm.dart      Aes256Gcm.overhead = 12 (nonce) + 16 (tag)
//	lib/crypto/src/padding.dart      MessagePadding.buckets.last = 65536
const (
	// mailboxIDLen is the mailbox id length in bytes; in URLs it is hex,
	// mailboxIDLen*2 characters.
	mailboxIDLen = 16

	// maxPacketSize is the largest packet the app can produce:
	// header (1 + 16) + nonce (12) + largest padded payload (65536) + tag (16)
	// = 65581 bytes. The app only sends 301, 1069, 4141, 16429 or 65581
	// bytes, but the relay does not look at the packet beyond its length.
	maxPacketSize = 1 + mailboxIDLen + 12 + 65536 + 16
)

// Defaults. See relay/README.md for why each value was chosen.
const (
	// packetTTL covers the app's fetch window: inboxMailboxes asks for
	// today's and yesterday's mailbox (lib/features/chat/messaging_service.dart).
	packetTTL = 48 * time.Hour

	defaultMaxPacketsPerMailbox = 1000
	defaultMaxMailboxBytes      = 8 << 20   // 8 MiB
	defaultMaxTotalBytes        = 512 << 20 // 512 MiB

	defaultRateLimit  = 120 // requests per client per rateWindow
	rateWindow        = time.Minute
	janitorInterval   = 30 * time.Second
	countersInterval  = 15 * time.Minute
	shutdownTimeout   = 10 * time.Second
	readHeaderTimeout = 5 * time.Second
	readTimeout       = 30 * time.Second
	writeTimeout      = 2 * time.Minute
	idleTimeout       = 60 * time.Second
	maxHeaderBytes    = 8 << 10 // 8 KiB
)

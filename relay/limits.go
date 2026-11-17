package main

import "time"

// Sizes taken from the app's packet format, version 3 (0004 §4 and §5).
// Keep in sync with:
//
//	lib/crypto/src/olm_wire_format.dart  PacketV3.mailboxIdLength = 16,
//	                                     headerLength = 1 (version) +
//	                                     16 (mailbox id) + 1 (Olm type),
//	                                     maxPacketSize = 65712
//	lib/crypto/src/olm_padding.dart      OlmPadding.buckets.last = 65536
const (
	// mailboxIDLen is the mailbox id length in bytes; in URLs it is hex,
	// mailboxIDLen*2 characters.
	mailboxIDLen = 16

	// olmMaxNormal is the largest normal Olm message (type 1, Olm version
	// 1): ciphertext 65536 (the padded text of 65535 bytes plus one byte of
	// PKCS7) + 45 + a chain index of up to 3 bytes + 3 bytes for the length
	// of the ciphertext.
	olmMaxNormal = 65536 + 45 + 3 + 3

	// olmMaxPreKey is the largest pre-key message (type 0): the normal
	// message + 104 + 3 bytes for its length.
	olmMaxPreKey = olmMaxNormal + 104 + 3

	// maxPacketSize is the largest packet the app can produce: header
	// (1 + 16 + 1) + the largest Olm message = 65712 bytes. The size of a
	// packet depends on the bucket, the Olm type and the chain index (0004
	// §4), but the relay does not look at the packet beyond its length.
	maxPacketSize = 1 + mailboxIDLen + 1 + olmMaxPreKey
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

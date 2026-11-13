# 0001 – Protocol, storage and transport: order and library

Status: **D1 Accepted by owner** (2026-11-13). **D2 amended by owner**
(2026-11-13): the standalone relay may be built now, see
[0002](0002-transport-v1.md). **D3 open – owner decides.** See Gate.

## Facts (with source)

Code, on branch `feat/recovery-trust-ui` (base `main` @ 1afaf6d):

- Identity is one static X25519 key pair; identity hash = SHA-256(public key).
  `lib/crypto/src/types.dart` (`PublicIdentity`), `sha_crypto_service.dart`.
- Per-pair keys: X25519 + HKDF-SHA256, separate message and mailbox keys per
  direction. `lib/crypto/src/key_agreement.dart`.
- Messages: padded, AES-256-GCM, packet `version || mailbox id || nonce ||
  ciphertext || tag`. `aes_gcm.dart`, `padding.dart`, `wire_format.dart`.
- Mailbox ids: HMAC-SHA256 per direction and UTC day, 16 bytes.
  `ShaCryptoService.mailboxId`, `WireFormat.epochOf`.
- Stored packets are re-opened with the same static keys, including the
  user's own sent messages (`MessageDirection.outgoing` → send key).
  `lib/features/chat/chat_controller.dart` (`build`),
  `lib/features/chat/messaging_service.dart` (`open`),
  `lib/crypto/src/sha_crypto_service.dart` (`open`).
- Contacts and messages live in memory only (`ContactsStore`, `MessageStore`
  start empty on every launch). The identity is persisted in the Keystore vault.
- No transport: `chat_controller.dart` – "Here the packet would be handed to
  the relay pool"; `transportAvailableProvider` is `false`.
- `Contact.id` = identity hash hex. A contact is created only after a QR
  scan (release builds; debug builds also allow manual code entry) and after
  the user confirms by eye that both phones show the same 20-digit code –
  the app does not compare the codes itself. `contacts_store.dart`,
  `lib/features/qr/scan_screen.dart`, `lib/features/qr/add_contact_sheet.dart`.
- QR format `shaid:1:<hash>:<public key>`. `lib/features/qr/contact_code.dart`.
- `inboxMailboxes` returns today's and yesterday's mailbox id per contact.
  `messaging_service.dart`.
- Fixed-interval polling, Tor/mixnet and no FCM are listed as next steps in
  `docs/SECURITY_REVIEW.md` ("Rekommenderade nästa steg" 2–3).

Libraries (fetched 2026-10-21 from the primary sources below; re-verify
before deciding; not legal advice):

- **libsignal** – `LICENSE` is GNU AGPL v3. README: "Use outside of Signal is
  unsupported" and "All APIs and implementations are subject to change
  without notice", with backwards-incompatible changes to the Java, Swift,
  TypeScript and non-bridge Rust APIs reflected in the version number "on a
  best-effort basis". Source: `raw.githubusercontent.com/signalapp/libsignal/main/{README.md,LICENSE}`.
- **vodozemac** (Matrix; Olm = Double Ratchet, plus Megolm) – `LICENSE` and
  `Cargo.toml` say Apache-2.0, version 0.11.1. README: "one security audit by
  Least Authority, with no significant findings". The README lists no
  language bindings. Source: `raw.githubusercontent.com/matrix-org/vodozemac/main/{README.md,LICENSE,Cargo.toml}`.
- **flutter_vodozemac** – pub.dev: version 0.9.0 (published 2026-10-19),
  publisher famedly.com, licence tag `agpl-3.0`, Android FFI plugin. It
  depends on the Dart package **vodozemac** 0.9.0, also famedly.com and also
  `agpl-3.0`, built with `flutter_rust_bridge`. Source:
  `pub.dev/api/packages/{flutter_vodozemac,vodozemac}` (+ `/score`, `/publisher`).

=> The permissive Rust core does not make the Flutter/Dart dependency
permissive: both published Dart packages are AGPL-3.0.

## Open questions

- Can a Double Ratchet session (libsignal or Olm) be started purely from keys
  exchanged in person via QR, with no key server or prekey upload? **Unverified.**
- Does the library need its own account/identity key format (e.g. an extra
  signing key) instead of SHA's X25519-only identity, and does that change
  the QR payload? **Unverified.**
- Maintenance status and release cadence of each option beyond the version
  numbers above. **Unverified.**
- Can a relay keep packets for the full polling window (today + yesterday)
  without that retention itself becoming a metadata risk? **Unverified** – a
  transport design question.
- Other libraries (none evaluated).

## Decisions needed from the owner

**D1 – Trust model.** *(Accepted by owner, 2026-11-13.)* A contact means "verified in person"; there is no
unverified or changed-key state. A new phone or a reset identity is a new key,
so the people involved must meet again. A future "replace existing contact"
flow (new in-person scan, explicit warning, old key retired) is needed but is
not designed here.

**D2 – Order: protocol → storage → transport.** *(Amended by owner,
2026-11-13, in [0002](0002-transport-v1.md): the relay server may be built
now as a standalone part, because it only stores opaque packets. App-side
storage and connecting the app to the relay still wait for D3.)* Proposed
because:

1. Today stored packets are re-opened with the static keys, including one's
   own sent messages. Under a Double Ratchet message keys are deleted after
   use, so history would have to be stored as plaintext encrypted at rest
   with a separate Keystore-wrapped key. Storage designed before the protocol
   would be redone.
2. The protocol may change the identity/QR format (`shaid:1`). Persisting
   contacts first would force a migration of every stored contact, and
   contacts can only be re-established by meeting again.
3. Mailbox derivation and polling depend on the protocol's key schedule.

**D3 – Library and licence.** Options:

- (a) Publish SHA as open source under an AGPL-compatible licence and use an
  AGPL library (libsignal, or flutter_vodozemac/vodozemac Dart packages).
- (b) Write own FFI bindings to the Apache-2.0 vodozemac crate: more work and
  new attack surface in the binding layer, to be reviewed like crypto code.
- (c) Evaluate other libraries (not done).

Rules that hold for every option: no hand-rolled ratchet, no new primitives;
an AI assistant must not invent cryptography for SHA.

**Transport constraints** (inputs to the transport decision, not decided here):

- Mailbox ids are unlinkable cryptographically, but polling several ids in
  one request, or from one IP address, links them for the relay.
- Because `inboxMailboxes` returns today's and yesterday's ids per contact
  (nothing calls it yet), relay retention must cover that polling window.
- Fixed-interval polling, Tor or a mixnet, and no FCM, per
  `docs/SECURITY_REVIEW.md`.

## Gate

- Allowed now (D2 as amended, [0002](0002-transport-v1.md)): the standalone
  relay server in `relay/`. It stores only opaque packets, decrypts nothing
  and is not connected to the app.
- Blocked until **D3** is marked **Accepted** by the owner: storage in the
  app and connecting the app to the relay. Until then no protocol library,
  database, HTTP/Tor client or other dependency is added to the app.

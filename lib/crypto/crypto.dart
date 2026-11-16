/// SHA cryptography module.
///
/// Everything cryptographic in the app lives under `lib/crypto/` (plus the
/// native Keystore code it calls) and is reached only through the types
/// exported here. The module has no UI, state management or business logic,
/// so it can be audited on its own.
library;

export 'src/android_keystore_vault.dart' show AndroidKeystoreVault;
export 'src/crypto_service.dart' show CryptoService;
export 'src/entropy.dart' show EntropySource;
export 'src/key_vault.dart' show KeyVault;
export 'src/olm_service.dart'
    show
        OlmContactBundle,
        OlmFailureCounts,
        OlmIncoming,
        OlmOutgoing,
        OlmReceiveFailure,
        OlmReceiveResult,
        OlmService,
        olmKeyLength;
export 'src/padding.dart' show MessagePadding;
export 'src/sha_crypto_service.dart' show ShaCryptoService;
export 'src/types.dart'
    show
        ConversationKeys,
        CryptoErrorKind,
        CryptoException,
        IdentityHash,
        KeyProtection,
        KeyProtectionLevel,
        MessageDirection,
        PublicIdentity,
        identityHashLength,
        publicKeyLength;
export 'src/wire_format.dart' show WireFormat;

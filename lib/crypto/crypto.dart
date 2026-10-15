/// SHA cryptography module.
///
/// Everything cryptographic in the app lives under `lib/crypto/` and is
/// reached only through the types exported here. The module has no UI, state
/// management or business logic, so it can be audited on its own.
library;

export 'src/crypto_service.dart' show CryptoService;
export 'src/secure_key_storage.dart'
    show AndroidKeystoreStorage, SecureKeyStorage;
export 'src/sha_crypto_service.dart' show ShaCryptoService;
export 'src/types.dart'
    show
        ConversationKey,
        CryptoException,
        IdentityHash,
        PublicIdentity,
        identityHashLength,
        publicKeyLength;

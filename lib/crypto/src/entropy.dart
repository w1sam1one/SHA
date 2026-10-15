import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'types.dart';
import 'wipe.dart';

/// A cryptographically secure random byte source.
abstract interface class EntropySource {
  Future<Uint8List> randomBytes(int length);
}

/// Dart VM CSPRNG (`Random.secure`, backed by the OS).
final class DartEntropySource implements EntropySource {
  DartEntropySource();

  final Random _random = Random.secure();

  @override
  Future<Uint8List> randomBytes(int length) async =>
      Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));
}

/// Randomness for long-term keys, drawn from two independent CSPRNG
/// implementations and combined with HKDF-SHA256:
///
///     out = HKDF(ikm = dart(64) || platform(64), info = purpose)
///
/// The output is unpredictable as long as *either* source is sound, which
/// protects key generation against a bug in one implementation (as happened
/// with Android's SecureRandom in 2013). Both sources are seeded by the
/// kernel, so this adds robustness, not new physical entropy.
final class MixedEntropy {
  MixedEntropy({required this._platform, EntropySource? local})
    : _local = local ?? DartEntropySource();

  static const int _sampleLength = 64;

  final EntropySource _platform;
  final EntropySource _local;

  Future<Uint8List> bytes(int length, {required String purpose}) async {
    if (length <= 0 || length > 255 * 32) {
      throw const CryptoException('Invalid random length');
    }
    final a = await _local.randomBytes(_sampleLength);
    final b = await _platform.randomBytes(_sampleLength);
    final ikm = Uint8List(2 * _sampleLength);
    try {
      if (!_plausible(a) || !_plausible(b) || _equal(a, b)) {
        throw const CryptoException(
          'Random source failed a sanity check',
          CryptoErrorKind.entropy,
        );
      }
      ikm
        ..setRange(0, _sampleLength, a)
        ..setRange(_sampleLength, 2 * _sampleLength, b);
      final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: length);
      final ikmKey = ownedKey(Uint8List.fromList(ikm));
      final out = await hkdf.deriveKey(
        secretKey: ikmKey,
        nonce: const [],
        info: utf8.encode('SHA/v2/rng/$purpose'),
      );
      ikmKey.destroy();
      final result = Uint8List.fromList(await out.extractBytes());
      out.destroy();
      return result;
    } finally {
      wipe(a);
      wipe(b);
      wipe(ikm);
    }
  }

  /// Rejects obviously broken output: wrong length or a constant byte.
  static bool _plausible(Uint8List bytes) =>
      bytes.length == _sampleLength && bytes.any((x) => x != bytes[0]);

  static bool _equal(Uint8List a, Uint8List b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

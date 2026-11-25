import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What Android says the app is signed with (F14, 0014 (2c)): the SHA-256
/// fingerprint of each signing certificate, in keytool's form, and whether
/// this is a debug build. Android computes nothing new here: it reports the
/// certificate it checked when the app was installed.
final class AppSignature {
  const AppSignature({required this.sha256, required this.debuggable});

  /// The phone's answer, checked before anything is shown.
  factory AppSignature.parse(Map<Object?, Object?> answer) {
    final list = answer['sha256'];
    if (list is! List || list.isEmpty) throw StateError('no fingerprint');
    final fingerprints = [
      for (final value in list)
        if (value is String && fingerprint.hasMatch(value))
          value
        else
          throw StateError('not a fingerprint'),
    ];
    return AppSignature(
      sha256: fingerprints,
      debuggable: answer['debuggable'] == true,
    );
  }

  /// "AB:CD:…": 32 bytes, upper case, with colons.
  static final RegExp fingerprint = RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$');

  final List<String> sha256;
  final bool debuggable;
}

abstract interface class AppSignaturePlatform {
  Future<AppSignature> read();
}

/// [AppSignaturePlatform] on Android (`AppSignatureChannel.kt`).
final class MethodChannelAppSignature implements AppSignaturePlatform {
  const MethodChannelAppSignature();

  static const MethodChannel _channel = MethodChannel(
    'se.sha.sha/app_signature',
  );

  @override
  Future<AppSignature> read() async {
    final answer = await _channel.invokeMapMethod<Object?, Object?>('read');
    return AppSignature.parse(answer ?? const {});
  }
}

final appSignaturePlatformProvider = Provider<AppSignaturePlatform>(
  (ref) => const MethodChannelAppSignature(),
);

/// No retries: an answer that cannot be read is shown as such at once,
/// and Android is asked once (review of #56).
final appSignatureProvider = FutureProvider<AppSignature>(
  (ref) => ref.read(appSignaturePlatformProvider).read(),
  retry: (count, error) => null,
);

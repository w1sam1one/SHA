import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sha/core/errors.dart';
import 'package:sha/crypto/crypto.dart';
import 'package:sha/features/chat/notice_texts.dart';
import 'package:sha/features/transport/relay_client.dart';

/// Guardrails for the security rules in lib/crypto/README.md.
void main() {
  List<File> dartFiles(String dir) => [
    for (final f in Directory(dir).listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart')) f,
  ];

  test('lib/ contains no logging calls', () {
    final banned = RegExp(
      r'\b(print|debugPrint|debugPrintStack)\s*\(|'
      r"\blog\s*\(|dart:developer|package:logging|stdout\.|stderr\.",
    );
    final offenders = [
      for (final file in dartFiles('lib'))
        for (final (i, line) in file.readAsLinesSync().indexed)
          if (banned.hasMatch(line)) '${file.path}:${i + 1}',
    ];
    expect(offenders, isEmpty);
  });

  test('crypto module does not depend on UI or app code', () {
    // Only the platform-channel binding (flutter/services.dart) is allowed.
    final banned = RegExp(
      r"^import 'package:(flutter/(?!services\.dart)|flutter_riverpod|sha/)|"
      r"^import '\.\./\.\./",
    );
    final offenders = [
      for (final file in dartFiles('lib/crypto'))
        for (final line in file.readAsLinesSync())
          if (banned.hasMatch(line)) '${file.path}: $line',
    ];
    expect(offenders, isEmpty);
  });

  test('no error object is put into a text (0004 §10)', () {
    // Error texts from Olm and from the network can contain keys, mailbox
    // IDs or addresses. They are turned into fixed texts, never shown. (The
    // app's own exceptions with a Swedish `message`, such as
    // ContactCodeException, are fine.)
    final banned = RegExp(
      r'\$\{?(e|err|error|exception|stack|stackTrace)\b|'
      r'\b(e|err|error|exception)\.toString\b',
    );
    final offenders = [
      for (final file in dartFiles('lib'))
        if (!file.path.startsWith('lib/crypto/'))
          for (final (i, line) in file.readAsLinesSync().indexed)
            if (banned.hasMatch(line)) '${file.path}:${i + 1}: $line',
    ];
    expect(offenders, isEmpty);
  });

  test('the texts a user sees hold no key material (0004 §10)', () {
    final keyLike = RegExp(r'[A-Za-z0-9+/=_-]{24,}');
    final texts = [
      for (final n in [0, 1, 2, 40])
        ...NoticeTexts.failures(
          'Jonas',
          OlmFailureCounts(unreadable: n, tooLate: n, gapTooBig: n),
        ),
      NoticeTexts.serverBusy,
      NoticeTexts.serverFull,
      for (final kind in CryptoErrorKind.values)
        describeError(CryptoException('key ${'A' * 43}', kind)),
      describeError(const RelayUnavailable()),
      describeError(StateError('mailbox ${'f' * 32}')),
    ];
    for (final t in texts) {
      expect(keyLike.hasMatch(t), isFalse, reason: t);
    }
    for (final e in const <RelayException>[
      RelayUnavailable(),
      RelayFull(),
      RelayBusy(Duration(seconds: 1)),
    ]) {
      expect(keyLike.hasMatch(e.toString()), isFalse, reason: '$e');
    }
  });

  test('native Keystore code does not log', () {
    final banned = RegExp(r'\bLog\.|println\(|printStackTrace\(');
    final offenders = [
      for (final f in Directory(
        'android/app/src/main/kotlin',
      ).listSync(recursive: true))
        if (f is File && f.path.endsWith('.kt'))
          for (final (i, line) in f.readAsLinesSync().indexed)
            if (banned.hasMatch(line)) '${f.path}:${i + 1}',
    ];
    expect(offenders, isEmpty);
  });
}

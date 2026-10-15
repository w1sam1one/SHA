import '../crypto/crypto.dart';

/// Upper-case hex in groups of four: `7F3A 9C21 E4B8 …`.
List<String> hashGroups(IdentityHash hash) {
  final hex = hash.hex.toUpperCase();
  return [for (var i = 0; i < hex.length; i += 4) hex.substring(i, i + 4)];
}

/// Full hash as lines of [perLine] groups.
List<String> hashLines(IdentityHash hash, {int perLine = 4}) {
  final groups = hashGroups(hash);
  return [
    for (var i = 0; i < groups.length; i += perLine)
      groups.sublist(i, i + perLine).join(' '),
  ];
}

/// Short form for lists and headers: `7F3A 9C21 ··· 51B0 88D4`.
String shortHash(IdentityHash hash) {
  final groups = hashGroups(hash);
  return '${groups[0]} ${groups[1]} ··· ${groups[groups.length - 2]} ${groups.last}';
}

/// `482 913`
String formatVerificationCode(String code) =>
    '${code.substring(0, 3)} ${code.substring(3)}';

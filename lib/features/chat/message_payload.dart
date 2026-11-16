import 'dart:convert';

/// The text inside an Olm message, before padding (0004 §5):
///
///     {"v":3,"id":…,"t":…,"m":…}
///
/// The same fields as version 2: the message ID, the time sent in
/// microseconds since 1970 (UTC) and the text. The ID and the time travel
/// only encrypted.
final class MessagePayload {
  const MessagePayload({
    required this.id,
    required this.sentAt,
    required this.text,
  });

  static const int version = 3;

  final String id;

  /// In UTC after [decode].
  final DateTime sentAt;
  final String text;

  /// Ends with `}`, so the padding's spaces can be removed again.
  String encode() => jsonEncode({
    'v': version,
    'id': id,
    't': sentAt.toUtc().microsecondsSinceEpoch,
    'm': text,
  });

  /// Null for anything that is not a version 3 payload. Spaces after the
  /// JSON (the padding) are allowed.
  static MessagePayload? decode(String json) {
    final Object? value;
    try {
      value = jsonDecode(json);
    } on FormatException {
      return null;
    }
    if (value is! Map<String, Object?>) return null;
    final (v, id, t, m) = (value['v'], value['id'], value['t'], value['m']);
    if (v != version || id is! String || t is! int || m is! String) {
      return null;
    }
    return MessagePayload(
      id: id,
      sentAt: DateTime.fromMicrosecondsSinceEpoch(t, isUtc: true),
      text: m,
    );
  }
}

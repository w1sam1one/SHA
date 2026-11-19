import 'relay_client.dart';

/// How often the app fetches while it is open (0002): 1, 5, 15 or 60
/// minutes.
enum FetchInterval {
  one(Duration(minutes: 1), 'Varje minut'),
  five(Duration(minutes: 5), 'Var 5:e minut'),
  fifteen(Duration(minutes: 15), 'Var 15:e minut'),
  sixty(Duration(minutes: 60), 'Varje timme');

  const FetchInterval(this.duration, this.label);

  final Duration duration;
  final String label;
}

/// How long the history is kept (0010 (B), F3): the owner's choices, with
/// 30 days as the default. With [none] nothing is kept after it is shown or
/// sent, as before F3.
enum HistoryLength {
  none(Duration.zero, 'Spara inte'),
  week(Duration(days: 7), '7 dagar'),
  month(Duration(days: 30), '30 dagar'),
  year(Duration(days: 365), '1 år');

  const HistoryLength(this.duration, this.label);

  final Duration duration;
  final String label;

  bool get keeps => this != none;
}

/// Thrown by [TransportSettings.parseServer]. [message] is shown as is.
final class ServerAddressException implements Exception {
  const ServerAddressException(this.message);

  final String message;
}

/// The app's settings, saved in the Olm state entry (0005, item 9): the
/// server address, the fetch interval and how long the history is kept.
final class TransportSettings {
  const TransportSettings({
    this.server,
    this.interval = defaultInterval,
    this.history = defaultHistory,
  });

  static const FetchInterval defaultInterval = FetchInterval.five;
  static const HistoryLength defaultHistory = HistoryLength.month;

  /// Null until the user has set one: then nothing is sent or fetched.
  final Uri? server;
  final FetchInterval interval;
  final HistoryLength history;

  TransportSettings copyWith({
    Uri? server,
    FetchInterval? interval,
    HistoryLength? history,
  }) => TransportSettings(
    server: server ?? this.server,
    interval: interval ?? this.interval,
    history: history ?? this.history,
  );

  Map<String, String> toMap() => {
    if (server != null) 'server': server.toString(),
    'interval': '${interval.duration.inMinutes}',
    'history': '${history.duration.inDays}',
  };

  /// Anything unknown or broken falls back to the default.
  factory TransportSettings.fromMap(Map<String, String> map) {
    final raw = map['server'];
    final server = raw == null ? null : Uri.tryParse(raw);
    final minutes = int.tryParse(map['interval'] ?? '');
    final days = int.tryParse(map['history'] ?? '');
    return TransportSettings(
      server: server != null && HttpRelayClient.isAllowedServer(server)
          ? server
          : null,
      interval: FetchInterval.values.firstWhere(
        (i) => i.duration.inMinutes == minutes,
        orElse: () => defaultInterval,
      ),
      history: HistoryLength.values.firstWhere(
        (h) => h.duration.inDays == days,
        orElse: () => defaultHistory,
      ),
    );
  }

  /// The address as typed. `https://` is added when there is no scheme.
  static Uri parseServer(String text) {
    final trimmed = text.trim();
    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (trimmed.isEmpty ||
        uri == null ||
        !HttpRelayClient.isAllowedServer(uri)) {
      throw const ServerAddressException(
        'Skriv serverns adress, till exempel https://server.example.se. '
        'Adressen måste börja med https://.',
      );
    }
    return uri.replace(path: '');
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sha/features/transport/transport_settings.dart';

void main() {
  test('the four intervals of 0002, 5 minutes by default', () {
    expect(FetchInterval.values.map((i) => i.duration.inMinutes), [
      1,
      5,
      15,
      60,
    ]);
    expect(const TransportSettings().interval, FetchInterval.five);
    expect(const TransportSettings().server, isNull);
  });

  test('round-trips through the saved map', () {
    final s = TransportSettings(
      server: Uri.parse('https://server.example.se'),
      interval: FetchInterval.sixty,
      history: HistoryLength.year,
    );
    expect(s.toMap(), {
      'server': 'https://server.example.se',
      'interval': '60',
      'history': '365',
    });
    final back = TransportSettings.fromMap(s.toMap());
    expect(back.server, s.server);
    expect(back.interval, FetchInterval.sixty);
    expect(back.history, HistoryLength.year);
  });

  test('the history: the owner\'s four choices, 30 days by default '
      '(0010 (B))', () {
    expect(HistoryLength.values.map((h) => h.label), [
      'Spara inte',
      '7 dagar',
      '30 dagar',
      '1 år',
    ]);
    expect(TransportSettings.fromMap(const {}).history, HistoryLength.month);
    expect(
      TransportSettings.fromMap(const {'history': '12'}).history,
      HistoryLength.month,
    );
    expect(
      TransportSettings.fromMap(const {'history': '0'}).history,
      HistoryLength.none,
    );
    expect(HistoryLength.none.keeps, isFalse);
    expect(HistoryLength.week.keeps, isTrue);
  });

  test('anything broken in the saved map falls back to the default', () {
    final s = TransportSettings.fromMap({
      'server': 'http://server.example.se',
      'interval': '7',
    });
    expect(s.server, isNull);
    expect(s.interval, FetchInterval.five);
    expect(TransportSettings.fromMap({}).interval, FetchInterval.five);
  });

  test('parseServer adds https:// and refuses anything else', () {
    expect(
      TransportSettings.parseServer('  server.example.se  '),
      Uri.parse('https://server.example.se'),
    );
    expect(
      TransportSettings.parseServer('https://server.example.se:8443/'),
      Uri.parse('https://server.example.se:8443'),
    );
    for (final bad in [
      '',
      'http://server.example.se',
      'https://server.example.se/v1',
      'https://server.example.se?x=1',
      'ftp://server.example.se',
      'https://',
    ]) {
      expect(
        () => TransportSettings.parseServer(bad),
        throwsA(
          isA<ServerAddressException>().having(
            (e) => e.message,
            'message',
            'Skriv serverns adress, till exempel https://server.example.se. '
                'Adressen måste börja med https://.',
          ),
        ),
        reason: bad,
      );
    }
  });
}

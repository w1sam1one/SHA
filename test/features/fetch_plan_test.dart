// 0004 §9 (b): each mailbox at its own random time within the interval,
// and many contacts stay under the server's limit.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sha/features/transport/fetch_plan.dart';

/// The most requests in any 60 seconds, counting the next round too.
int busiestMinute(List<Duration> times) {
  final sorted = [...times]..sort();
  var most = 0;
  for (var i = 0, j = 0; i < sorted.length; i++) {
    while (sorted[i] - sorted[j] >= const Duration(minutes: 1)) {
      j++;
    }
    most = max(most, i - j + 1);
  }
  return most;
}

void main() {
  test('every mailbox once, inside the interval, in time order', () {
    final round = planRound(
      ['a', 'b', 'c'],
      const Duration(minutes: 5),
      Random(1),
    );
    expect(round.length, const Duration(minutes: 5));
    expect(round.requests.map((r) => r.item).toSet(), {'a', 'b', 'c'});
    expect(round.requests, hasLength(3));
    for (final r in round.requests) {
      expect(r.at, greaterThanOrEqualTo(Duration.zero));
      expect(r.at, lessThan(round.length));
    }
    final times = [for (final r in round.requests) r.at];
    expect(times, [...times]..sort());
  });

  test('the order and the times change from round to round', () {
    final random = Random(2);
    final items = List.generate(10, (i) => i);
    final a = planRound(items, const Duration(minutes: 1), random);
    final b = planRound(items, const Duration(minutes: 1), random);
    expect(
      a.requests.map((r) => r.item).toList(),
      isNot(b.requests.map((r) => r.item).toList()),
    );
    expect(
      a.requests.map((r) => r.at).toList(),
      isNot(b.requests.map((r) => r.at).toList()),
    );
  });

  test('no mailboxes: an empty round of the interval', () {
    final round = planRound(<int>[], const Duration(minutes: 15), Random(3));
    expect(round.requests, isEmpty);
    expect(round.length, const Duration(minutes: 15));
  });

  test('many contacts do not reach the limit of 120 a minute', () {
    final random = Random(4);
    for (final contacts in [1, 30, 60, 61, 100, 500]) {
      final mailboxes = List.generate(2 * contacts, (i) => i);
      // Three rounds in a row, as the app would run them.
      final times = <Duration>[];
      var start = Duration.zero;
      for (var r = 0; r < 3; r++) {
        final round = planRound(mailboxes, const Duration(minutes: 1), random);
        times.addAll([for (final q in round.requests) start + q.at]);
        start += round.length;
      }
      expect(
        busiestMinute(times),
        lessThanOrEqualTo(110),
        reason: '$contacts contacts',
      );
    }
  });
}

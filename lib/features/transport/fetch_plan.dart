import 'dart:math';

/// One round of requests: each at its own time (0004 §9 (b)).
final class FetchRound<T> {
  const FetchRound(this.length, this.requests);

  /// When the next round starts.
  final Duration length;

  /// In time order.
  final List<({T item, Duration at})> requests;
}

/// Plans a round: every item (a mailbox) is fetched once, at a random time,
/// in a random order (0004 §9 (b)).
///
/// The round is split into one slot per item, and each item gets a random
/// time inside its slot. So no minute has more than [perMinute] + 1
/// requests, and many contacts stay under the server's limit of 120 per
/// minute (relay/limits.go): the round is made longer instead.
FetchRound<T> planRound<T>(
  List<T> items,
  Duration interval,
  Random random, {
  int perMinute = 100,
}) {
  final shuffled = [...items]..shuffle(random);
  final needed = Duration(
    microseconds: (shuffled.length * Duration.microsecondsPerMinute / perMinute)
        .ceil(),
  );
  final length = needed > interval ? needed : interval;
  if (shuffled.isEmpty) return FetchRound(length, const []);
  final slot = length.inMicroseconds ~/ shuffled.length;
  return FetchRound(length, [
    for (final (i, item) in shuffled.indexed)
      (
        item: item,
        at: Duration(microseconds: i * slot + random.nextInt(max(slot, 1))),
      ),
  ]);
}

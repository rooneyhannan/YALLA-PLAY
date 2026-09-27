import 'dart:math' as math;

/// Where the bouncing ball is at a moment of the song.
class BallState {
  /// Position across the strings: 0 = high E … 5 = low E, fractional while
  /// the ball flies from one string to another.
  final double string;

  /// Height above the board in pixels at the front of the board.
  final double height;

  /// Time since the last landing, or null before the first one.
  final double? sinceLanding;

  /// Index of the landing the ball last touched, or null before the first.
  final int? landed;
  const BallState(this.string, this.height, this.sinceLanding, this.landed);
}

/// The ball hops from note to note like a thrown ball: every hop is a
/// parabola in time under constant gravity, so it rises fast, slows to a
/// stop at the top and speeds up again as it falls onto the next note.
/// Across the strings it moves at constant speed, as a thrown ball does.
class BallPath {
  /// Times (in ticks) at which the ball touches a note, in order.
  final List<double> landings;

  /// String of each landing.
  final List<int> strings;

  /// Pull of gravity in pixels per tick². A hop of duration T reaches
  /// gravity · T² / 8, the height of a real throw.
  final double gravity;

  /// Long pauses would throw the ball off the screen; above this height
  /// the hop keeps its parabola but flattens.
  final double maxHeight;

  const BallPath({
    required this.landings,
    required this.strings,
    this.gravity = 90,
    this.maxHeight = 150,
  }) : assert(landings.length == strings.length);

  /// The hop from [start] into the first note, dropped from rest.
  double get start => math.max(0, landings.first - 6);

  double hopHeight(double duration) =>
      math.min(gravity * duration * duration / 8, maxHeight);

  BallState at(double t) {
    if (landings.isEmpty) return const BallState(0, 0, null, null);
    // Before the first note the ball falls from rest onto it: the second
    // half of a hop, starting at its apex.
    if (t < landings.first) {
      final fall = landings.first - start;
      final s = ((t - start) / fall).clamp(0.0, 1.0);
      return BallState(
        strings.first.toDouble(),
        hopHeight(fall * 2) * (1 - s * s),
        null,
        null,
      );
    }
    var k = _lastLandingAtOrBefore(t);
    if (k == landings.length - 1) {
      // Resting on the last note.
      return BallState(strings[k].toDouble(), 0, t - landings[k], k);
    }
    final t0 = landings[k], t1 = landings[k + 1];
    final s = (t - t0) / (t1 - t0);
    return BallState(
      strings[k] + (strings[k + 1] - strings[k]) * s,
      hopHeight(t1 - t0) * 4 * s * (1 - s),
      t - t0,
      k,
    );
  }

  int _lastLandingAtOrBefore(double t) {
    var low = 0, high = landings.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (landings[mid] <= t) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }
}

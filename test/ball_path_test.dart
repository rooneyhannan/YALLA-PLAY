import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_play/features/game/data/ball_path.dart';
import 'package:yalla_play/features/game/presentation/highway_painter.dart';

void main() {
  final path = BallPath(
    landings: [6, 10, 12, 28],
    strings: [2, 0, 0, 5],
    gravity: 90,
    maxHeight: 200,
  );

  test('the ball touches each note exactly when it is due', () {
    for (final (i, t) in path.landings.indexed) {
      final state = path.at(t);
      expect(state.height, 0, reason: 'landing $i');
      expect(state.string, path.strings[i].toDouble());
      expect(state.landed, i);
    }
  });

  test('each hop is a parabola: slowest at the top, fastest at the ends', () {
    // Hop from tick 6 to 10 (4 ticks): apex at 8, height g·T²/8.
    expect(path.at(8).height, closeTo(90 * 16 / 8, 1e-9));
    double speed(double t) =>
        (path.at(t + .01).height - path.at(t).height).abs();
    expect(speed(7.99), lessThan(.01));
    expect(speed(6.1), greaterThan(speed(7)));
    expect(speed(9.8), greaterThan(speed(9)));
    // Symmetric: rising and falling mirror each other.
    expect(path.at(7).height, closeTo(path.at(9).height, 1e-9));
  });

  test('short gaps give small hops, long ones are capped', () {
    expect(path.at(11).height, closeTo(90 * 4 / 8, 1e-9));
    expect(path.at(20).height, 200);
  });

  test('moves across the strings at constant speed', () {
    expect(path.at(7).string, closeTo(1.5, 1e-9));
    expect(path.at(8).string, closeTo(1, 1e-9));
    expect(path.at(20).string, closeTo(2.5, 1e-9));
  });

  test('drops onto the first note and rests after the last', () {
    expect(path.at(path.start).height, greaterThan(0));
    expect(path.at(5).height, lessThan(path.at(3).height));
    expect(path.at(40).height, 0);
    expect(path.at(40).string, 5);
  });

  test('strings recede: the thin ones lie at the back of the board', () {
    const board = BoardProjection(200, 400, 100);
    final high = BoardProjection.stringDepth(0);
    final low = BoardProjection.stringDepth(5);
    expect(board.y(high), lessThan(board.y(low)));
    // Lanes get narrower towards the back.
    final gapBack = board.y(BoardProjection.stringDepth(1)) - board.y(high);
    final gapFront = board.y(low) - board.y(BoardProjection.stringDepth(4));
    expect(gapBack, lessThan(gapFront));
    // Beat lines lean inwards towards the back.
    expect(board.project(100, 1).dx, lessThan(board.project(100, 0).dx));
  });
}

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_play/features/game/data/fingering.dart';
import 'package:yalla_play/features/game/data/song_chart.dart';
import 'package:yalla_play/features/game/data/song_data.dart';

import 'demo_chart.dart';

void main() {
  test('one finger per fret, open strings need none', () {
    // Frets 1–4 fit first position: index to pinky.
    final notes = [
      const Note(2, 1, 1),
      const Note(2, 2, 1),
      const Note(1, 0, 1),
      const Note(2, 3, 1),
      const Note(2, 4, 1),
    ];
    expect(assignFingers(notes), [1, 2, 0, 3, 4]);
  });

  test('shifts the hand only when a note does not fit', () {
    // 5–8 cannot be played from first position: the hand moves up once
    // and plays them all with fingers 1–4.
    final notes = [
      for (final f in [5, 6, 7, 8, 6, 5]) Note(1, f, 1),
    ];
    expect(assignFingers(notes), [1, 2, 3, 4, 2, 1]);
  });

  test('every note of the song gets a finger in reach', () {
    final fingers = assignFingers(rawSongData);
    expect(fingers, hasLength(rawSongData.length));
    for (var i = 0; i < fingers.length; i++) {
      final fret = rawSongData[i].f;
      expect(fingers[i], fret == 0 ? 0 : inInclusiveRange(1, 4));
    }
  });

  test('every shift with the same finger, index first', () {
    // Up from fret 3 to 5: the index slides along.
    final lamma = [3, 5, 6, 8, 6, 6, 5, 5, 3, 3, 2, 3];
    expect(assignFingers(_notes(lamma)), [1, 1, 2, 4, 2, 2, 1, 1, 1, 1, 1, 2]);
    expect(_checkShifts(lamma).slides, [1, 1, 1]);
    // Down from fret 8 to 3: the pinky cannot slide there, so the index
    // slides 5 → 6 and the ring finger 8 → 3.
    expect(assignFingers(_notes([5, 6, 7, 8, 3])), [1, 1, 2, 3, 3]);
    // Fret 1–3, then 5–6: the ring finger slides with one shift (3 → 5).
    expect(assignFingers(_notes([1, 2, 3, 5, 6])), [1, 2, 3, 3, 4]);
    // Index rather than pinky.
    expect(assignFingers(_notes([1, 2, 4, 5])), [1, 1, 3, 4]);
    expect(assignFingers(_notes([1, 2, 3, 4, 5])), [1, 1, 2, 3, 4]);
  });

  test('the pinky slides only where it saves two shifts', () {
    // 1, 2, 4, then a jump to 8: two index shifts rather than one pinky
    // shift.
    expect(assignFingers(_notes([1, 2, 4, 8])), [1, 1, 3, 3]);
    // Up to 4, a jump to 8 and back to 5: the pinky slides 4 → 8, as every
    // other way needs three shifts.
    expect(assignFingers(_notes([1, 1, 1, 4, 8, 5])), [1, 1, 1, 4, 4, 1]);
    final run = [for (var f = 1; f <= 10; f++) f];
    final got = _checkShifts(run);
    expect(got.pinky, 0);
    expect(got.weight, _fewestShifts(run));
  });

  for (final id in ['badak', 'lamma-bada']) {
    test('$id: every shift with the same finger, as few as possible', () {
      final chart = SongChart.parse(
        File('assets/songs/$id.json').readAsStringSync(),
      );
      final frets = [for (final n in chart.notes) n.note.f];
      final got = _checkShifts(frets, id);
      expect(got.weight, _fewestShifts(frets));
      expect(got.pinky, 0);
      // Slides, not jumps: the hand moves one fret, with the index.
      expect(got.moves.every((m) => m.abs() == 1), isTrue);
      expect(got.slides.every((f) => f == 1), isTrue);
    });
  }

  test('random tunes keep the rules with the fewest shifts', () {
    var seed = 7;
    double random() => (seed = (seed * 16807) % 2147483647) / 2147483647;
    for (var n = 0; n < 300; n++) {
      var f = 1 + (random() * 12).floor();
      final frets = <int>[];
      final length = 4 + (random() * 30).floor();
      for (var i = 0; i < length; i++) {
        if (random() < .15) {
          frets.add(0);
          continue;
        }
        f = math.min(20, math.max(1, f + ((random() - .5) * 10).round()));
        frets.add(f);
      }
      expect(_checkShifts(frets, frets.join(',')).weight, _fewestShifts(frets));
    }
  });
}

List<Note> _notes(List<int> frets) => [for (final f in frets) Note(1, f, 1)];

/// Checks Rooney's rule between every two fretted notes: every shift with
/// the same finger. Returns which finger slid at each shift and how far.
({List<int> slides, List<int> moves, int pinky, double weight}) _checkShifts(
  List<int> frets, [
  String label = '',
]) {
  final fingers = assignFingers(_notes(frets));
  final slides = <int>[], moves = <int>[];
  int? last;
  for (var i = 0; i < frets.length; i++) {
    if (frets[i] == 0) {
      expect(fingers[i], 0);
      continue;
    }
    expect(fingers[i], inInclusiveRange(1, 4), reason: '$label note $i');
    if (last != null) {
      final move = (frets[i] - fingers[i]) - (frets[last] - fingers[last]);
      if (move != 0) {
        expect(fingers[i], fingers[last], reason: '$label note $i');
        slides.add(fingers[i]);
        moves.add(move);
      }
    }
    last = i;
  }
  final pinky = slides.where((f) => f == 4).length;
  return (
    slides: slides,
    moves: moves,
    pinky: pinky,
    weight: slides.length + 1.5 * pinky,
  );
}

/// The least weight of shifts that keeps the rule, worked out on its own:
/// a pinky shift weighs two and a half.
double _fewestShifts(List<int> frets) {
  final fretted = frets.where((f) => f > 0).toList();
  if (fretted.isEmpty) return 0;
  // (hand position, finger of the last note) → least weight.
  var best = <(int, int), double>{
    for (var k = 1; k <= 4; k++)
      if (fretted.first - k + 1 >= 1) (fretted.first - k + 1, k): 0,
  };
  for (var i = 1; i < fretted.length; i++) {
    final next = <(int, int), double>{};
    for (final MapEntry(key: (q, last), value: n) in best.entries) {
      for (var k = 1; k <= 4; k++) {
        final p = fretted[i] - k + 1;
        if (p < 1 || (p != q && k != last)) continue;
        final c = n + (p == q ? 0 : (k == 4 ? 2.5 : 1));
        if (c < (next[(p, k)] ?? double.infinity)) next[(p, k)] = c;
      }
    }
    best = next;
  }
  return best.values.reduce(math.min);
}

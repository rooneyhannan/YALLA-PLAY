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

  test('the hand never shifts against the fingers', () {
    // The opening of Lamma Bada: fret 5 to 8 with a shift never goes
    // finger 3 → 2; the hand moves with the melody and the same finger
    // slides along.
    final lamma = [3, 5, 6, 8, 6, 6, 5, 5, 3, 3, 2, 3];
    expect(assignFingers(_notes(lamma)), [1, 1, 2, 4, 4, 4, 4, 4, 2, 2, 1, 2]);
    expect(_checkShifts(lamma), _fewestShifts(lamma));
    // Down from fret 8 (pinky) to 3: never a higher finger, and as little
    // change as possible (pinky → ring).
    expect(assignFingers(_notes([5, 6, 7, 8, 3])), [1, 2, 3, 4, 3]);
    // Up fret by fret: the fingers never go back down (no pinky → index).
    final run = [1, 2, 3, 4, 5, 6];
    expect(assignFingers(_notes(run)), [1, 2, 3, 3, 4, 4]);
    expect(_checkShifts(run), _fewestShifts(run));
  });

  for (final id in ['badak', 'lamma-bada']) {
    test('$id: every shift keeps the rules, as few as possible', () {
      final chart = SongChart.parse(
        File('assets/songs/$id.json').readAsStringSync(),
      );
      final frets = [for (final n in chart.notes) n.note.f];
      expect(_checkShifts(frets, id), _fewestShifts(frets));
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
      expect(_checkShifts(frets, frets.join(',')), _fewestShifts(frets));
    }
  });
}

List<Note> _notes(List<int> frets) => [for (final f in frets) Note(1, f, 1)];

/// Checks Rooney's rule between every two fretted notes: up the neck never
/// to a lower finger, down never to a higher one. Returns the shifts.
int _checkShifts(List<int> frets, [String label = '']) {
  final fingers = assignFingers(_notes(frets));
  var shifts = 0;
  int? last;
  for (var i = 0; i < frets.length; i++) {
    if (frets[i] == 0) {
      expect(fingers[i], 0);
      continue;
    }
    expect(fingers[i], inInclusiveRange(1, 4), reason: '$label note $i');
    if (last != null) {
      final move = (frets[i] - fingers[i]) - (frets[last] - fingers[last]);
      final step = frets[i] - frets[last];
      if (move != 0) {
        shifts++;
        final where = '$label note $i';
        // With the melody, and the finger changes along with it: up the
        // neck never to a lower finger, down never to a higher one.
        expect(move.sign, step.sign, reason: where);
        final change = fingers[i] - fingers[last];
        expect(change * step.sign, greaterThanOrEqualTo(0), reason: where);
      }
    }
    last = i;
  }
  return shifts;
}

/// The fewest shifts that keep the rule, worked out on its own.
int _fewestShifts(List<int> frets) {
  final fretted = frets.where((f) => f > 0).toList();
  if (fretted.isEmpty) return 0;
  bool fits(int p, int f) => f >= p && f <= p + 3;
  var best = <int, int>{};
  for (var p = 1; p <= 21; p++) {
    if (fits(p, fretted.first)) best[p] = 0;
  }
  for (var k = 1; k < fretted.length; k++) {
    final step = fretted[k] - fretted[k - 1];
    final next = <int, int>{};
    for (final MapEntry(key: q, value: n) in best.entries) {
      for (var p = 1; p <= 21; p++) {
        if (!fits(p, fretted[k])) continue;
        final move = p - q;
        final against = move.sign != step.sign || move.abs() > step.abs();
        if (move != 0 && against) continue;
        final c = n + (move != 0 ? 1 : 0);
        if (c < (next[p] ?? c + 1)) next[p] = c;
      }
    }
    best = next;
  }
  return best.values.reduce((a, b) => a < b ? a : b);
}

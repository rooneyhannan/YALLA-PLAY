import 'dart:io';

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

  test('the hand shifts with the melody, never pinky 5 to index 6', () {
    // The opening of Lamma Bada: 2–8 needs a shift. Pinky on fret 5 and
    // index on fret 6 straight after (the hand jumping four frets for one)
    // is not how anyone plays it; the hand moves where the melody does.
    final notes = [
      for (final f in [3, 5, 6, 8, 6, 6, 5, 5, 3, 3, 2, 3]) Note(1, f, 1),
    ];
    expect(assignFingers(notes), [1, 3, 4, 4, 2, 2, 1, 1, 2, 2, 1, 2]);
  });

  for (final id in ['badak', 'lamma-bada']) {
    test('$id: every shift is natural', () {
      final chart = SongChart.parse(
        File('assets/songs/$id.json').readAsStringSync(),
      );
      final notes = [for (final n in chart.notes) n.note];
      final fingers = assignFingers(notes);
      int? last;
      for (var i = 0; i < notes.length; i++) {
        if (notes[i].f == 0) continue;
        if (last != null) {
          final a = notes[last], b = notes[i];
          final hand = (b.f - fingers[i]) - (a.f - fingers[last]);
          final step = b.f - a.f;
          if (hand != 0) {
            final where =
                'note $i: ${a.f}/${fingers[last]} → ${b.f}/${fingers[i]}';
            // With the melody, and the finger changes by at most one.
            expect(step.sign, hand.sign, reason: where);
            expect((step - hand).abs(), lessThanOrEqualTo(1), reason: where);
          }
        }
        last = i;
      }
    });
  }
}

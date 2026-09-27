import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_play/features/game/data/fingering.dart';
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
}

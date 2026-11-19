import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_play/core/models/song.dart';
import 'package:yalla_play/features/game/data/song_chart.dart';

import 'demo_chart.dart';

void main() {
  test('the demo song reads from its JSON file', () {
    expect(demoChart.id, 'badak');
    expect(demoChart.notes, hasLength(57));
    expect(demoChart.bpm, 90);
    // 90 beats a minute, four ticks each: the game's old six a second.
    expect(demoChart.ticksPerSecond, 6);
    final first = demoChart.notes.first;
    expect(
      (first.tick, first.note.s, first.note.f, first.note.d),
      // D4, in the 10th position where the whole tune lies without a shift.
      (0, 4, 12, 4),
    );
  });

  test('every chart in the song list is a valid file of that id', () {
    final charts = [for (final s in songs) ?s.chart];
    expect(charts, containsAll(['badak', 'lamma-bada', 'bint-shalabiya']));
    for (final id in charts) {
      final chart = SongChart.parse(
        File('assets/songs/$id.json').readAsStringSync(),
      );
      expect(chart.id, id);
    }
  });

  test('Lamma Bada comes in 10/8, a bar of ten eighths', () {
    final chart = SongChart.parse(
      File('assets/songs/lamma-bada.json').readAsStringSync(),
    );
    expect((chart.ticksPerBeat, chart.beatsPerBar, chart.bpm), (2, 10, 96));
    expect(chart.notes, hasLength(207));
    expect(chart.chords, isEmpty);
    // 18 bars: twice the first part of five bars, then the second of eight.
    final last = chart.notes.last;
    expect(last.tick + last.note.d, 18 * 20);
    // Its fourth bar stays on F sharp, the leading note of G minor: an
    // accidental in ABC holds to the end of the bar.
    const open = [64, 59, 55, 50, 45, 40];
    final bar = [
      for (final n in chart.notes)
        if (n.tick >= 60 && n.tick < 80) (open[n.note.s - 1] + n.note.f) % 12,
    ];
    expect(bar, containsAll([6, 7, 3, 2]));
    expect(bar, isNot(contains(5)));
  });

  test('Al Bint el Shalabiya: 4/4 at 150, repeats written out', () {
    final chart = SongChart.parse(
      File('assets/songs/bint-shalabiya.json').readAsStringSync(),
    );
    expect((chart.ticksPerBeat, chart.beatsPerBar, chart.bpm), (2, 4, 150));
    expect(chart.notes, hasLength(287));
    expect(chart.chords, isEmpty);
    // 55 bars: the intro of six, the verse twice with its two endings, the
    // second part, the verse again from the sign and the coda; the last
    // note ends on the third beat of the last bar.
    final last = chart.notes.last;
    expect(last.tick + last.note.d, 54 * 8 + 4);
    // C minor with B natural as its leading note, never B flat.
    const open = [64, 59, 55, 50, 45, 40];
    final pitches = {
      for (final n in chart.notes) (open[n.note.s - 1] + n.note.f) % 12,
    };
    expect(pitches, containsAll([0, 2, 3, 5, 7, 8, 11]));
    expect(pitches, isNot(contains(10)));
  });

  test('rests, fingers and other tempos come through', () {
    final chart = SongChart.parse('''
      {"format": "yalla-song/1", "id": "x", "title": "X", "bpm": 120,
       "ticksPerBeat": 2, "beatsPerBar": 3,
       "notes": [{"t": 8, "s": 1, "f": 0, "d": 2},
                 {"t": 0, "s": 6, "f": 3, "d": 1, "finger": 2}]}''');
    expect(chart.ticksPerSecond, 4);
    expect(chart.beatsPerBar, 3);
    expect(chart.artist, '');
    // Ordered by time, with the gap kept.
    expect([for (final n in chart.notes) n.tick], [0, 8]);
    expect(chart.notes.first.finger, 2);
    expect(chart.notes.last.finger, isNull);
  });

  test('says what is wrong with a broken file', () {
    void rejects(String json, String message) => expect(
      () => SongChart.parse(json),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains(message),
        ),
      ),
    );
    rejects('{"format": "other"}', 'Not a yalla-song/1 file');
    rejects(
      '{"format": "yalla-song/1", "id": "x", "title": "X", "bpm": 90, "notes": []}',
      'no notes',
    );
    rejects(
      '{"format": "yalla-song/1", "id": "x", "title": "X", "bpm": 90,'
          ' "notes": [{"t": 0, "s": 7, "f": 0, "d": 1}]}',
      'out of range',
    );
    rejects(
      '{"format": "yalla-song/1", "id": "x", "title": "X",'
          ' "notes": [{"t": 0, "s": 1, "f": 0, "d": 1}]}',
      '"bpm"',
    );
  });
}

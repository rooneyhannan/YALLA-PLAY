import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_play/features/game/data/arrangement.dart';
import 'package:yalla_play/features/game/data/chord_symbol.dart';
import 'package:yalla_play/features/game/data/song_chart.dart';
import 'package:yalla_play/features/game/data/synth.dart';

void main() {
  test('chord names read as musicians write them', () {
    Set<int> tones(String name) => ChordSymbol.tryParse(name)!.tones;
    expect(tones('C'), {0, 4, 7});
    expect(tones('Dm'), {2, 5, 9});
    expect(tones('A7'), {9, 1, 4, 7});
    expect(tones('Bb'), {10, 2, 5});
    expect(tones('F#m7'), {6, 9, 1, 4});
    expect(tones('Gsus4'), {7, 0, 2});
    expect(tones('Cadd9'), {0, 4, 7, 2});
    final slash = ChordSymbol.tryParse('C/E')!;
    expect((slash.root, slash.bassNote), (0, 4));
    for (final bad in ['H', 'Cx', 'c', '', 'C//E', 'Dmm']) {
      expect(ChordSymbol.tryParse(bad), isNull, reason: bad);
    }
  });

  test('a song file carries its chords, and rejects unknown ones', () {
    final chart = SongChart.parse(
      '''
      {"format": "yalla-song/1", "id": "x", "title": "X", "bpm": 90,
       "notes": [{"t": 0, "s": 1, "f": 5, "d": 4}],
       "chords": [{"t": 16, "d": 16, "name": "A7"}, {"t": 0, "d": 16, "name": "Dm"}]}''',
    );
    expect([for (final c in chart.chords) c.chord.name], ['Dm', 'A7']);
    expect(
      () => SongChart.parse('''
        {"format": "yalla-song/1", "id": "x", "title": "X", "bpm": 90,
         "notes": [{"t": 0, "s": 1, "f": 5, "d": 4}],
         "chords": [{"t": 0, "d": 4, "name": "Hmoll"}]}'''),
      throwsA(isA<FormatException>()),
    );
  });

  group("backing from the song's own chords", () {
    // A4 (pitch class 9) asked for at tick 8; D minor, then a gap, then
    // C with E in the bass.
    final melody = <MelodyNote>[(start: 8, length: 4, frequency: 440)];
    final arrangement = Arrangement.of(
      melody,
      firstBeat: 0,
      end: 64,
      chords: [
        (start: 0, length: 16, chord: ChordSymbol.tryParse('Dm')!),
        (start: 32, length: 16, chord: ChordSymbol.tryParse('C/E')!),
      ],
    );
    List<int> classesAt(double tick, Voice voice) => [
      for (final e in arrangement.events)
        if (e.tick == tick && e.voice == voice) pitchClass(e.frequency),
    ];

    test('plays exactly those chords', () {
      expect(classesAt(0, Voice.chord).toSet(), {2, 5, 9});
      expect(classesAt(32, Voice.chord).toSet(), {0, 4, 7});
    });

    test('leaves out the note the player is asked for', () {
      // A is part of D minor, but the player plays A at tick 8.
      expect(classesAt(8, Voice.chord), isNot(contains(9)));
      expect(classesAt(8, Voice.chord), isNotEmpty);
    });

    test('is silent where the song has no chord', () {
      expect(classesAt(16, Voice.chord), isEmpty);
      expect(classesAt(20, Voice.chord), isEmpty);
    });

    test('plays the slash note in the bass', () {
      expect(classesAt(32, Voice.bass), [4]);
    });
  });
}

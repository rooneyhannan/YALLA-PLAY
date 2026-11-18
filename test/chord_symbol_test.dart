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
    // What the guitar and the strings start on the beat from [tick].
    Set<int> chordAt(double tick) => {
      for (final e in arrangement.events)
        if (e.tick >= tick - 1e-6 &&
            e.tick < tick + 4 - 1e-6 &&
            (e.voice == Voice.chord || e.voice == Voice.strings))
          pitchClass(e.frequency),
    };

    test('plays exactly those chords', () {
      expect(chordAt(0), {2, 5, 9});
      expect(chordAt(32), {0, 4, 7});
    });

    test('leaves out the note the player is asked for', () {
      // A is part of D minor, but the player plays A at tick 8.
      expect(chordAt(8), isNot(contains(9)));
      expect(chordAt(8), isNotEmpty);
    });

    test('is silent where the song has no chord', () {
      final gap = arrangement.events.where(
        (e) => e.voice != Voice.click && e.voice != Voice.accent,
      );
      for (final e in gap) {
        expect(
          e.tick + e.length <= 16 + 1e-6 || e.tick >= 32 - 1e-6,
          isTrue,
          reason: '${e.voice.name} at ${e.tick}',
        );
      }
    });

    test('plays the slash note in the bass', () {
      expect([
        for (final e in arrangement.events)
          if (e.tick == 32 && e.voice == Voice.bass) pitchClass(e.frequency),
      ], [4]);
    });
  });

  test('a second and a third voice sing under a long note', () {
    // A4 held for two beats in bar 5, a strummed bar, over F major: F4 a
    // third below, C4 under that, never the A the player plays.
    final arrangement = Arrangement.of(
      [(start: 64, length: 8, frequency: 440)],
      firstBeat: 0,
      end: 128,
      chords: [(start: 0, length: 128, chord: ChordSymbol.tryParse('F')!)],
    );
    final voices = [
      for (final e in arrangement.events)
        if (e.voice == Voice.harmony) (e.tick, pitchClass(e.frequency)),
    ];
    expect(voices, unorderedEquals([(64.0, 5), (64.0, 0)]));
  });
}

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_play/features/game/data/arrangement.dart';
import 'package:yalla_play/features/game/data/backing_style.dart';
import 'package:yalla_play/features/game/data/note_judge.dart';
import 'package:yalla_play/features/game/data/sound_engine.dart';
import 'package:yalla_play/features/game/data/sound_scheduler.dart';
import 'package:yalla_play/features/game/data/synth.dart';

import 'demo_chart.dart';

List<MelodyNote> songMelody() {
  var t = 6.0;
  return [
    for (final n in rawSongData)
      (() {
        final note = (
          start: t,
          length: n.d.toDouble(),
          frequency: noteFrequency(n),
        );
        t += n.d;
        return note;
      })(),
  ];
}

class RecordingEngine implements SoundEngine {
  final played = <(Voice, double)>[];
  bool silenced = false;
  @override
  Future<void> start() async {}
  @override
  double? get time => 10;
  @override
  void prepare(Voice voice, double frequency) {}
  @override
  void play(
    Voice voice,
    double frequency, {
    required double at,
    required double length,
    required double gain,
  }) => played.add((voice, at));
  @override
  void silence() => silenced = true;
  @override
  void dispose() {}
}

void main() {
  final melody = songMelody();
  final end = melody.last.start + melody.last.length + 6;
  final arrangement = Arrangement.of(melody, firstBeat: 6, end: end);

  const backingVoices = {
    Voice.chord,
    Voice.picked,
    Voice.bass,
    Voice.strings,
    Voice.harmony,
  };
  const darbuka = {Voice.doum, Voice.tek, Voice.ka};

  test('the backing never sounds a pitch the player is asked for', () {
    final backing = arrangement.events.where(
      (e) => backingVoices.contains(e.voice),
    );
    expect(
      {for (final e in backing) e.voice},
      containsAll({Voice.chord, Voice.bass, Voice.strings}),
    );
    expect(backing, isNotEmpty);
    for (final e in backing) {
      for (final n in melody) {
        // The note's pitch is listened for from a little before it starts
        // until its late window has passed.
        final listened =
            n.start - 1.2 < e.tick + e.length &&
            n.start + math.max(n.length, 2.1) > e.tick;
        if (listened) {
          expect(
            pitchClass(e.frequency),
            isNot(pitchClass(n.frequency)),
            reason: '${e.voice.name} at ${e.tick} against note at ${n.start}',
          );
        }
      }
    }
  });

  test('the backing is full: most beats have a chord of two tones or more', () {
    final perBeat = <int, Set<int>>{};
    for (final e in arrangement.events.where(
      (e) => e.voice == Voice.chord || e.voice == Voice.strings,
    )) {
      (perBeat[((e.tick - 6) / 4 + 1e-6).floor()] ??= {}).add(
        pitchClass(e.frequency),
      );
    }
    final beats = ((melody.last.start + melody.last.length - 6) / 4).ceil();
    final full = perBeat.values.where((n) => n.length >= 2).length;
    expect(full / beats, greaterThan(.6));
  });

  test('one guitar strums while the other picks, in every bar', () {
    // A strum sounds several strings within a few hundredths of a second,
    // picking one at a time.
    int count(Voice voice, int bar, int eighth) => arrangement.events
        .where(
          (e) =>
              e.voice == voice &&
              e.tick >= 6 + bar * 16 + eighth * 2 - 1e-6 &&
              e.tick < 6 + bar * 16 + eighth * 2 + .5,
        )
        .length;
    expect(count(Voice.chord, 4, 0), greaterThanOrEqualTo(2));
    final bars = ((melody.last.start + melody.last.length - 6) / 16).ceil();
    for (var bar = 0; bar < bars - 1; bar++) {
      expect(count(Voice.picked, bar, 0), lessThanOrEqualTo(1));
    }
    // No more bars of only one of them: both guitars play throughout.
    bool plays(Voice voice, int bar) => arrangement.events.any(
      (e) =>
          e.voice == voice &&
          e.tick >= 6 + bar * 16 - 1e-6 &&
          e.tick < 6 + (bar + 1) * 16 - 1e-6,
    );
    final both = [
      for (var bar = 0; bar < bars - 1; bar++)
        if (plays(Voice.chord, bar) && plays(Voice.picked, bar)) bar,
    ];
    expect(both.length / (bars - 1), greaterThan(.9));
  });

  test('the strumming is full: a stroke on every eighth, strong on doum', () {
    final bars = ((melody.last.start + melody.last.length - 6) / 16).ceil();
    // Maqsum, D T k T D k T k: the doums take all six strings, down.
    List<SoundEvent> stroke(int bar, int eighth) => arrangement.events
        .where(
          (e) =>
              e.voice == Voice.chord &&
              e.tick >= 6 + bar * 16 + eighth * 2 - 1e-6 &&
              e.tick < 6 + bar * 16 + eighth * 2 + .5,
        )
        .toList();
    var full = 0, strokes = 0;
    for (var bar = 0; bar < bars - 1; bar++) {
      for (var eighth = 0; eighth < 8; eighth++) {
        if (stroke(bar, eighth).isNotEmpty) strokes++;
      }
      // A doum strikes at least three strings, even with the player's
      // pitch left out.
      if (stroke(bar, 0).length >= 3) full++;
      final doum = stroke(bar, 0), ka = stroke(bar, 2);
      if (doum.isNotEmpty && ka.isNotEmpty) {
        expect(doum.first.gain, greaterThan(ka.first.gain * 1.5));
      }
    }
    expect(strokes / ((bars - 1) * 8), greaterThan(.9));
    expect(full / (bars - 1), greaterThan(.7));
  });

  test('a darbuka plays Maqsum in 4/4, through every bar', () {
    final drum = arrangement.events.where((e) => darbuka.contains(e.voice));
    final bars = ((melody.last.start + melody.last.length - 6) / 16).ceil();
    String bar(int b) => [
      for (var eighth = 0; eighth < 8; eighth++)
        switch (drum
            .where(
              (e) =>
                  e.tick >= 6 + b * 16 + eighth * 2 - 1e-6 &&
                  e.tick < 6 + b * 16 + eighth * 2 + .5,
            )
            .map((e) => e.voice)
            .firstOrNull) {
          Voice.doum => 'D',
          Voice.tek => 'T',
          Voice.ka => 'k',
          _ => '.',
        },
    ].join();
    for (var b = 0; b < bars - 1; b++) {
      expect(bar(b), 'DTkTDkTk', reason: 'bar $b');
    }
    expect(bar(bars - 1), 'D.......');
  });

  test('the song chooses guitars, rhythm and darbuka', () {
    Arrangement styled(BackingStyle style) =>
        Arrangement.of(melody, firstBeat: 6, end: end, style: style);
    final bars = ((melody.last.start + melody.last.length - 6) / 16).ceil();
    Set<Voice> voices(Arrangement a) => {for (final e in a.events) e.voice};
    final strum = voices(
      styled(const BackingStyle(guitar: BackingGuitar.strum)),
    );
    expect(strum, contains(Voice.chord));
    expect(strum, isNot(contains(Voice.picked)));
    final picked = styled(const BackingStyle(guitar: BackingGuitar.arpeggio));
    expect(voices(picked), contains(Voice.picked));
    // Only the final chord is strummed.
    for (final e in picked.events.where((e) => e.voice == Voice.chord)) {
      expect(e.tick, greaterThanOrEqualTo(6 + (bars - 1) * 16 - 1e-6));
    }
    final off = voices(styled(const BackingStyle(guitar: BackingGuitar.off)));
    expect(off.intersection({Voice.chord, Voice.picked}), isEmpty);
    expect(off, contains(Voice.bass));
    final quiet = voices(styled(const BackingStyle(darbuka: false)));
    expect(quiet.intersection(darbuka), isEmpty);
    final baladi = styled(const BackingStyle(rhythm: BackingRhythm.baladi));
    expect(
      baladi.events
          .where((e) => e.voice == Voice.doum && e.tick >= 22 && e.tick < 38)
          .length,
      3,
      reason: 'D D k T D k T k',
    );
  });

  test('rhythms: named ones fit their bar, others fall back', () {
    expect(BackingStyle.pattern(BackingRhythm.auto, 8), 'DTkTDkTk');
    expect(BackingStyle.pattern(BackingRhythm.auto, 10), 'DkkTkDDkTk');
    expect(BackingStyle.pattern(BackingRhythm.saidi, 8), 'DTkDDkTk');
    expect(BackingStyle.pattern(BackingRhythm.maqsum, 6), 'DkTkTk');
    expect(BackingStyle.pattern(BackingRhythm.maqsum, 5), 'DkTkT');
    expect(
      BackingStyle.fromJson({'guitar': 'strum', 'rhythm': 'wahda'}).rhythm,
      BackingRhythm.wahda,
    );
    expect(
      () => BackingStyle.fromJson({'rhythm': 'polka'}),
      throwsFormatException,
    );
    expect(
      () => BackingStyle.fromJson({'darbuka': 'ja'}),
      throwsFormatException,
    );
    expect(BackingStyle.fromJson(null).guitar, BackingGuitar.both);
  });

  test('played by hand: strokes vary a little, never before the beat', () {
    final strokes = arrangement.events.where(
      (e) => e.voice == Voice.chord || e.voice == Voice.picked,
    );
    expect({for (final e in strokes) e.gain}.length, greaterThan(10));
    for (final e in strokes) {
      final offGrid = (e.tick - 6) % 2;
      expect(offGrid, lessThan(.5), reason: '${e.voice.name} at ${e.tick}');
    }
    // The same song always sounds the same.
    final again = Arrangement.of(melody, firstBeat: 6, end: end);
    expect(
      [for (final e in again.events) (e.tick, e.gain)],
      [for (final e in arrangement.events) (e.tick, e.gain)],
    );
  });

  test('strings hold the chord over the beats', () {
    final strings = arrangement.events.where((e) => e.voice == Voice.strings);
    expect(strings, isNotEmpty);
    expect(strings.where((e) => e.length >= 4), isNotEmpty);
    for (final e in strings) {
      // At most three seconds a bow, so the sound lasts even at half speed.
      expect(e.length, lessThanOrEqualTo(3 * 6 + 1e-6));
    }
  });

  test('the metronome stresses the first beat of every bar', () {
    final clicks = arrangement.events.where(
      (e) => e.voice == Voice.click || e.voice == Voice.accent,
    );
    for (final c in clicks) {
      expect((c.tick - 6) % 4, 0);
      expect(c.voice == Voice.accent, (c.tick - 6) % 16 == 0);
    }
  });

  test('chords come from the key, one per bar', () {
    expect(arrangement.chords, isNotEmpty);
    for (final c in arrangement.chords) {
      expect(c.chord.tones, hasLength(3));
      expect(c.length, 16);
    }
  });

  test('the backing adds no tone foreign to the chord', () {
    // Leaving out the player's pitch must not turn the chord into another,
    // as a seventh would (A minor without A plus G sounds like C major).
    for (final e in arrangement.events.where(
      (e) =>
          e.voice == Voice.chord ||
          e.voice == Voice.picked ||
          e.voice == Voice.strings ||
          e.voice == Voice.harmony,
    )) {
      final span = arrangement.chords.lastWhere(
        (c) => c.start <= e.tick + 1e-6,
      );
      expect(
        span.chord.tones,
        contains(pitchClass(e.frequency)),
        reason: 'chord tone at ${e.tick} under ${span.chord}',
      );
    }
  });

  test('sounds are synthesized, finite and not clipping', () {
    for (final voice in Voice.values) {
      final samples = synthesize(voice, 220, 48000);
      expect(samples, isNotEmpty);
      final peak = samples.map((v) => v.abs()).reduce(math.max);
      expect(peak, inInclusiveRange(.1, 1.0), reason: voice.name);
    }
  });

  test('the scheduler plays each event once, on the audio clock', () {
    final engine = RecordingEngine();
    final scheduler = SoundScheduler(arrangement.events)..seek(0);
    scheduler.run(
      engine,
      tick: 0,
      until: 6,
      now: 10,
      ticksPerSecond: 6,
      enabled: (_) => true,
    );
    final first = engine.played.length;
    expect(first, greaterThan(0));
    // The metronome click at tick 2 sounds a third of a second later.
    expect(engine.played.first.$2, closeTo(10 + 2 / 6, 1e-9));
    scheduler.run(
      engine,
      tick: 3,
      until: 6,
      now: 10.5,
      ticksPerSecond: 6,
      enabled: (_) => true,
    );
    expect(engine.played.length, first, reason: 'nothing twice');
  });
}

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_play/features/game/data/arrangement.dart';
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
      expect(count(Voice.chord, bar, 1), 0, reason: 'no up-stroke after one');
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

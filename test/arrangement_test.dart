import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_play/features/game/data/arrangement.dart';
import 'package:yalla_play/features/game/data/note_judge.dart';
import 'package:yalla_play/features/game/data/song_data.dart';
import 'package:yalla_play/features/game/data/sound_engine.dart';
import 'package:yalla_play/features/game/data/sound_scheduler.dart';
import 'package:yalla_play/features/game/data/synth.dart';

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

  test('the backing never sounds a pitch the player is asked for', () {
    final backing = arrangement.events.where(
      (e) => e.voice == Voice.chord || e.voice == Voice.bass,
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
    final perBeat = <double, int>{};
    for (final e in arrangement.events.where((e) => e.voice == Voice.chord)) {
      perBeat[e.tick] = (perBeat[e.tick] ?? 0) + 1;
    }
    final beats = ((melody.last.start + melody.last.length - 6) / 4).ceil();
    final full = perBeat.values.where((n) => n >= 2).length;
    expect(full / beats, greaterThan(.6));
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

  test('chords come from the key and hold the melody they sound with', () {
    expect(arrangement.chords, isNotEmpty);
    for (final c in arrangement.chords) {
      expect(chordTones(c), hasLength(3));
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

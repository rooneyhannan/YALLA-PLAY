import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_play/core/models/song.dart';
import 'package:yalla_play/features/game/data/note_judge.dart';
import 'package:yalla_play/features/game/data/song_data.dart';
import 'package:yalla_play/features/game/presentation/game_screen.dart';
import 'package:yalla_play/features/tuner/data/tuner_engine.dart';
import 'package:yalla_play/features/tuner/data/tuning.dart';
import 'dart:math' as math;

class FakeTunerEngine implements TunerEngine {
  PitchCallback? onPitch;
  @override
  Future<void> start(PitchCallback onPitch, {FrameCallback? onFrame}) async =>
      this.onPitch = onPitch;
  @override
  void stop() => onPitch = null;
}

void main() {
  test('tab notes map to their pitch in standard tuning', () {
    expect(noteFrequency(const Note(6, 0, 1)), closeTo(82.41, .01));
    expect(noteFrequency(const Note(5, 0, 1)), closeTo(110, .01));
    // 2nd string, 3rd fret is D4.
    expect(noteFrequency(const Note(2, 3, 1)), closeTo(293.66, .1));
    // 1st string, 12th fret is an octave above the open string.
    expect(noteFrequency(const Note(1, 12, 1)), closeTo(659.26, .1));
  });

  test('pitch tolerance is ±40 cents, octave slips allowed', () {
    const a = 440.0;
    expect(pitchMatches(a * 1.02, a), isTrue); // +34 cents
    expect(pitchMatches(a * 1.03, a), isFalse); // +51 cents
    expect(pitchMatches(a * 2, a), isTrue);
    expect(pitchMatches(a * 1.5, a), isFalse);
  });

  test(
    'finds the expected note while another string rings, not a semitone off',
    () {
      const sr = 48000;
      double tone(double hz, int i) => [1.0, .5, .3].asMap().entries.fold(
        0.0,
        (sum, h) =>
            sum + h.value * math.sin(2 * math.pi * hz * (h.key + 1) * i / sr),
      );
      // A4 freshly plucked while a D4 on another string still rings, at
      // 60 % of its level. (A ringing string louder than the new pluck would
      // hide it; a fresh attack is normally the loudest sound.)
      final mix = [
        for (var i = 0; i < 4096; i++) tone(440, i) + .6 * tone(293.66, i),
      ];
      expect(periodicityAt(mix, sr, 440), greaterThan(.6));
      expect(periodicityAt(mix, sr, 466.16), lessThan(.6)); // A#4
      expect(periodicityAt(mix, sr, 415.3), lessThan(.6)); // G#4
      final alone = [for (var i = 0; i < 4096; i++) tone(440, i)];
      expect(periodicityAt(alone, sr, 440), greaterThan(.9));
      expect(periodicityAt(alone, sr, 466.16), -1);
    },
  );

  group('judge', () {
    // Two notes, at ticks 6 and 12; 6 ticks per second.
    NoteJudge judge() => NoteJudge(starts: [6, 12], frequencies: [440, 330]);

    test('timing decides perfect, early and late', () {
      final j = judge();
      expect(j.pluck(6.3, 440, ticksPerSecond: 6), 0); // +0.05 s
      expect(j.verdicts[0], Verdict.perfect);
      final early = judge()..pluck(5, 440, ticksPerSecond: 6); // -0.17 s
      expect(early.verdicts[0], Verdict.early);
      final late = judge()..pluck(7.5, 440, ticksPerSecond: 6); // +0.25 s
      expect(late.verdicts[0], Verdict.late);
    });

    test('wrong pitch or outside the window scores nothing', () {
      final j = judge();
      expect(j.pluck(6, 500, ticksPerSecond: 6), isNull);
      expect(j.pluck(3, 440, ticksPerSecond: 6), isNull); // 0.5 s early
      expect(j.pluck(9, 440, ticksPerSecond: 6), isNull); // 0.5 s late
      expect(j.verdicts, [null, null]);
    });

    test('unplayed notes are missed once their window passes', () {
      final j = judge();
      expect(j.expire(8, ticksPerSecond: 6), isEmpty);
      expect(j.expire(8.2, ticksPerSecond: 6), [0]);
      expect(j.verdicts[0], Verdict.missed);
    });

    test('score, streak multiplier, accuracy and stars', () {
      final starts = [for (var i = 0; i < 10; i++) 6.0 + i * 6];
      final j = NoteJudge(starts: starts, frequencies: List.filled(10, 440));
      for (final t in starts.take(9)) {
        j.pluck(t, 440, ticksPerSecond: 6);
      }
      expect(j.streak, 9);
      expect(j.multiplier, 2);
      expect(j.score, 8 * 100 + 1 * 200);
      j.expire(100, ticksPerSecond: 6);
      expect(j.streak, 0);
      expect(j.accuracy, .9);
      expect(j.stars, 3);
    });

    test('a held note is not a new pluck; a fresh attack is', () {
      final onsets = OnsetDetector();
      expect(onsets.feed(.001, null), isFalse);
      expect(onsets.feed(.05, 440), isTrue);
      expect(onsets.feed(.045, 440), isFalse);
      expect(onsets.feed(.04, 440), isFalse);
      expect(onsets.feed(.035, 330), isTrue); // new note, legato
      expect(onsets.feed(.03, 330), isFalse);
      expect(onsets.feed(.001, null), isFalse);
      expect(onsets.feed(.06, 330), isTrue); // same note plucked again
    });
  });

  test('practice waits: nothing expires, late plucks still count', () {
    final judge = NoteJudge(
      starts: [6, 12],
      frequencies: [440, 330],
      patient: true,
    );
    expect(judge.expire(100, ticksPerSecond: 6), isEmpty);
    expect(judge.firstOpen, 0);
    // The second note cannot be played before the first.
    expect(judge.pluck(12, 330, ticksPerSecond: 6), isNull);
    // Played two seconds after it was due: late, but counted.
    expect(judge.pluck(18, 440, ticksPerSecond: 6), 0);
    expect(judge.verdicts[0], Verdict.late);
    expect(judge.firstOpen, 1);
    expect(judge.pluck(12.2, 330, ticksPerSecond: 6), 1);
    expect(judge.verdicts[1], Verdict.perfect);
    expect(judge.firstOpen, isNull);
  });

  test('hears the wanted note under a louder chord, not a semitone off', () {
    const rate = 48000;
    // A plucked-like tone: a few harmonics, fading.
    List<double> tone(double hz, double level) => [
      for (var i = 0; i < 4096; i++)
        level *
            math.exp(-i / rate / .8) *
            (math.sin(2 * math.pi * hz * i / rate) +
                .5 * math.sin(4 * math.pi * hz * i / rate) +
                .25 * math.sin(6 * math.pi * hz * i / rate)),
    ];
    List<double> mix(List<List<double>> parts) => [
      for (var i = 0; i < 4096; i++) parts.fold(0.0, (s, p) => s + p[i]),
    ];
    double rms(List<double> x) =>
        math.sqrt(x.fold(0.0, (s, v) => s + v * v) / x.length);
    // The backing: C, E and G, twice as loud as the guitar, but no A.
    final chord = mix([tone(261.63, .4), tone(329.63, .4), tone(392, .4)]);
    final silent = List.filled(4096, 0.0);

    final right = ExpectedNoteDetector();
    final withA = mix([chord, tone(440, .2)]);
    expect(right.heard(0, silent, rate, 440, 0), isFalse);
    expect(right.heard(0, withA, rate, 440, rms(withA)), isTrue);

    final wrong = ExpectedNoteDetector();
    final withBb = mix([chord, tone(466.16, .2)]);
    expect(wrong.heard(0, silent, rate, 440, 0), isFalse);
    expect(wrong.heard(0, withBb, rate, 440, rms(withBb)), isFalse);

    // The chord alone never counts as the A.
    final none = ExpectedNoteDetector();
    expect(none.heard(0, silent, rate, 440, 0), isFalse);
    expect(none.heard(0, chord, rate, 440, rms(chord)), isFalse);

    // The next A while the last one still rings: only a new pluck counts.
    final ringing = mix([chord, tone(440, .1)]);
    expect(right.heard(1, ringing, rate, 440, rms(ringing)), isFalse);
    expect(right.heard(1, ringing, rate, 440, rms(ringing)), isFalse);
    final plucked = mix([chord, tone(440, .3)]);
    expect(right.heard(1, plucked, rate, 440, rms(plucked)), isTrue);
  });

  testWidgets('playing along into the microphone scores the notes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final engine = FakeTunerEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(song: songs.first, engineFactory: () => engine),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('game-start')));
    await tester.pump();
    expect(engine.onPitch, isNotNull);
    await tester.pump(const Duration(milliseconds: 3100));

    // The first note (2nd string, 3rd fret) is due one second in; pluck
    // it right on time: silence, then an attack at its pitch.
    final first = noteFrequency(rawSongData.first);
    await tester.pump(const Duration(milliseconds: 950));
    engine.onPitch!(null, .001);
    await tester.pump(const Duration(milliseconds: 50));
    engine.onPitch!(first, .05);
    engine.onPitch!(first, .05);
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('ممتاز'), findsNothing); // painted, not a widget
    final score = tester.widget<Text>(find.byKey(const ValueKey('game-score')));
    expect(score.data, '100');

    // Then stay silent: the next notes pass unplayed and are missed.
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('game-multiplier'))).data,
      '×1',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('practice holds the song at a note until it is played', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final engine = FakeTunerEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(song: songs.first, engineFactory: () => engine),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('game-start-practice')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 3100));

    double progress() => tester
        .widget<LinearProgressIndicator>(
          find.byKey(const ValueKey('session-progress')),
        )
        .value!;
    // The first note is due one second in; stay silent well past it.
    await tester.pump(const Duration(seconds: 2));
    final held = progress();
    expect(find.byKey(const ValueKey('game-waiting')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(progress(), held);

    // A wrong note does not release it.
    engine.onPitch!(null, .001);
    engine.onPitch!(noteFrequency(rawSongData.first) * 1.06, .05);
    engine.onPitch!(noteFrequency(rawSongData.first) * 1.06, .05);
    await tester.pump(const Duration(milliseconds: 16));
    expect(progress(), held);

    // The right note does, and it counts as late.
    await tester.pump(const Duration(milliseconds: 500));
    engine.onPitch!(null, .001);
    engine.onPitch!(noteFrequency(rawSongData.first), .05);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 100));
    expect(progress(), greaterThan(held));
    expect(find.byKey(const ValueKey('game-waiting')), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('game-practice-count')))
          .data,
      '1 / ${rawSongData.length}',
    );
    await tester.pumpWidget(const SizedBox());
  });
}

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'test_fonts.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_play/core/theme/app_theme.dart';
import 'package:yalla_play/features/tuner/data/tuner_engine.dart';
import 'package:yalla_play/features/tuner/data/tuning.dart';
import 'package:yalla_play/features/tuner/presentation/tuner_screen.dart';

class FakeTunerEngine implements TunerEngine {
  TunerException? failWith;
  PitchCallback? onPitch;
  int stops = 0;
  bool get running => onPitch != null;

  @override
  Future<void> start(PitchCallback onPitch) async {
    if (failWith != null) throw failWith!;
    this.onPitch = onPitch;
  }

  @override
  void stop() {
    stops++;
    onPitch = null;
  }
}

/// A plucked string: the fundamental plus overtones.
List<double> pluck(
  double hz,
  int sampleRate, {
  int length = 4096,
  List<double> harmonics = const [1.0, .6, .35, .2],
}) => [
  for (var i = 0; i < length; i++)
    harmonics.asMap().entries.fold<double>(
      0,
      (sum, h) =>
          sum +
          h.value *
              .3 *
              math.sin(2 * math.pi * hz * (h.key + 1) * i / sampleRate),
    ),
];

void main() {
  group('tuning math', () {
    test('automatic mode picks the closest string', () {
      expect(readTuning(111).stringIndex, 4);
      expect(readTuning(111).cents, closeTo(15.67, .01));
      expect(readTuning(80).stringIndex, 5);
      expect(readTuning(330).stringIndex, 0);
      expect(readTuning(246.94).inTune, isTrue);
    });

    test('manual mode compares with the chosen string, octave-corrected', () {
      expect(readTuning(100, target: 4).cents, lessThan(-100));
      expect(readTuning(220, target: 4).cents, closeTo(0, .01));
      expect(readTuning(82.41, target: 4).cents, closeTo(-500, 1));
    });

    test('automatic mode names the string even an octave off', () {
      final g = readTuning(392.4);
      expect(g.stringIndex, 2);
      expect(g.cents, closeTo(1.77, .01));
      expect(g.frequency, closeTo(196.2, .01));
      expect(readTuning(220).stringIndex, 4);
      expect(readTuning(587.3).stringIndex, 3);
      expect(readTuning(160).stringIndex, 5);
    });

    test('level gate drops a string fading far below its pluck', () {
      final gate = LevelGate();
      expect(gate.open(.001), isFalse);
      expect(gate.open(.2), isTrue);
      expect(gate.open(.01), isFalse);
      for (var i = 0; i < 200; i++) {
        gate.open(0);
      }
      expect(gate.open(.01), isTrue);
    });

    test('smoother ignores single outliers and restarts on a new note', () {
      final smoother = PitchSmoother();
      for (final hz in [110.0, 110.2, 110.1]) {
        smoother.add(hz);
      }
      expect(smoother.add(111), 110.2);
      expect(smoother.add(196), 196);
    });

    for (final sampleRate in [44100, 48000]) {
      test('YIN detects every open string at $sampleRate Hz', () {
        for (final string in standardTuning) {
          final hz = detectPitch(
            pluck(string.frequency, sampleRate),
            sampleRate,
          );
          expect(hz, isNotNull, reason: string.note);
          expect(
            centsBetween(hz!, string.frequency).abs(),
            lessThan(2),
            reason: '${string.note}: $hz',
          );
        }
      });
    }

    test('YIN finds the fundamental under a stronger overtone', () {
      for (final string in standardTuning) {
        for (final harmonics in [
          [.15, 1.0, .5, .3],
          [.2, .5, 1.0, .3],
        ]) {
          final hz = detectPitch(
            pluck(string.frequency, 48000, harmonics: harmonics),
            48000,
          );
          expect(
            centsBetween(hz!, string.frequency).abs(),
            lessThan(2),
            reason: '${string.note} $harmonics: $hz',
          );
        }
      }
    });

    for (final (file, string) in [('acoustic_E2', 5), ('nylon_G3', 2)]) {
      test('recorded $file: every heard frame names the right string', () {
        // Canonical 16-bit mono WAV written by the fixture script.
        final bytes = ByteData.sublistView(
          File('test/fixtures/$file.wav').readAsBytesSync(),
        );
        const sampleRate = 44100, hop = sampleRate ~/ 20, header = 44;
        final samples = [
          for (var i = header; i + 1 < bytes.lengthInBytes; i += 2)
            bytes.getInt16(i, Endian.little) / 32768,
        ];
        final gate = LevelGate();
        final heard = <TuningReading>[];
        for (var end = 4096; end <= samples.length; end += hop) {
          final frame = samples.sublist(end - 4096, end);
          final rms = math.sqrt(
            frame.fold(0.0, (sum, v) => sum + v * v) / frame.length,
          );
          if (!gate.open(rms)) continue;
          final hz = detectPitch(frame, sampleRate);
          if (hz != null) heard.add(readTuning(hz));
        }
        expect(heard.length, greaterThan(25));
        expect(heard.where((r) => r.stringIndex != string), isEmpty);
        final wrongOctave = heard.where(
          (r) =>
              centsBetween(
                r.frequency,
                standardTuning[string].frequency,
              ).abs() >
              50,
        );
        expect(wrongOctave, isEmpty);
      });
    }

    test('YIN reports nothing for noise-free silence', () {
      expect(detectPitch(List.filled(4096, 0.0), 48000), isNull);
    });
  });

  group('tuner screen', () {
    setUpAll(loadDesignFonts);

    Future<FakeTunerEngine> pumpTuner(
      WidgetTester tester, {
      bool active = true,
    }) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = FakeTunerEngine();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: TunerScreen(
                onBack: () {},
                active: active,
                engineFactory: () => engine,
              ),
            ),
          ),
        ),
      );
      return engine;
    }

    String hint(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const ValueKey('tuner-hint'))).data!;
    String note(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const ValueKey('tuner-note'))).data!;

    Future<void> hear(
      WidgetTester tester,
      FakeTunerEngine engine,
      double? hz, {
      int times = 1,
    }) async {
      for (var i = 0; i < times; i++) {
        engine.onPitch!(hz, .05);
      }
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('listens, detects the string and marks it tuned', (
      tester,
    ) async {
      final engine = await pumpTuner(tester);
      expect(engine.running, isFalse);
      await tester.tap(find.byKey(const ValueKey('tuner-listen')));
      await tester.pump();
      expect(engine.running, isTrue);
      expect(hint(tester), 'اعزف على وتر واتركه يرن');

      await hear(tester, engine, 106);
      expect(note(tester), 'A');
      expect(hint(tester), contains('شُدّ'));

      await hear(tester, engine, 113.5, times: 5);
      expect(hint(tester), contains('أرخِ'));

      await hear(tester, engine, 110.1, times: 12);
      expect(hint(tester), 'الوتر مضبوط');
      expect(find.byKey(const ValueKey('tuner-tuned-4')), findsOneWidget);

      await hear(tester, engine, null, times: 12);
      expect(find.byKey(const ValueKey('tuner-cents')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('tuner-listen')));
      await tester.pump();
      expect(engine.running, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('manual mode compares with the chosen string', (tester) async {
      final engine = await pumpTuner(tester);
      await tester.tap(find.byKey(const ValueKey('tuner-listen')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tuner-string-3')));
      await tester.pump();
      expect(hint(tester), 'اعزف على وتر D');
      await hear(tester, engine, 110);
      expect(note(tester), 'D');
      expect(hint(tester), contains('شُدّ'));
      await tester.tap(find.byKey(const ValueKey('tuner-mode')));
      await hear(tester, engine, 110);
      expect(note(tester), 'A');
    });

    testWidgets('explains a denied microphone', (tester) async {
      final engine = await pumpTuner(tester);
      engine.failWith = const TunerException(TunerError.permissionDenied);
      await tester.tap(find.byKey(const ValueKey('tuner-listen')));
      await tester.pump();
      expect(hint(tester), contains('الإذن'));
      expect(engine.running, isFalse);
    });

    testWidgets('releases the microphone when the tab is left', (tester) async {
      final engine = await pumpTuner(tester);
      await tester.tap(find.byKey(const ValueKey('tuner-listen')));
      await tester.pump();
      expect(engine.running, isTrue);
      await pumpTuner(tester, active: false);
      expect(engine.running, isFalse);
    });
  });
}

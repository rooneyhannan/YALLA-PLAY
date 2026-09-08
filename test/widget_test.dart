import 'test_fonts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_play/main.dart';
import 'package:yalla_play/features/game/presentation/game_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDesignFonts);
  testWidgets('Every main tab fits mobile and desktop sizes', (tester) async {
    for (final size in [const Size(390, 844), const Size(1440, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(const YallaGuitarApp());
      await tester.pumpAndSettle();
      expect(find.text('Yalla Guitar'), findsOneWidget);
      for (var tab = 0; tab < 4; tab++) {
        await tester.tap(find.byKey(ValueKey('nav-$tab')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Layout of tab $tab at $size');
      }
      await tester.pumpWidget(const SizedBox());
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('A library song opens guitar preview; pause and restart work', (tester) async {
    await tester.pumpWidget(const YallaGuitarApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('song-life')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('Life by the Drop'), findsWidgets);
    expect(find.byKey(const ValueKey('guitar-board')), findsOneWidget);
    double progress() => tester.widget<LinearProgressIndicator>(find.byKey(const ValueKey('session-progress'))).value!;
    await tester.pump(const Duration(seconds: 1));
    expect(progress(), greaterThan(0));
    await tester.tap(find.byKey(const ValueKey('game-toggle')));
    await tester.pump();
    final paused = progress();
    await tester.pump(const Duration(seconds: 3));
    expect(progress(), paused);
    await tester.tap(find.byKey(const ValueKey('game-restart')));
    await tester.pump();
    expect(progress(), 0);
    await tester.tap(find.byKey(const ValueKey('game-back')));
    await tester.pumpAndSettle();
    expect(find.byType(GameScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Playback advances by elapsed time, independently of frame count', (tester) async {
    await tester.pumpWidget(const YallaGuitarApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('daily-start')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('game-restart')));
    await tester.pump();
    double progress() => tester.widget<LinearProgressIndicator>(find.byKey(const ValueKey('session-progress'))).value!;
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 100)); }
    final tenFrames = progress();
    await tester.tap(find.byKey(const ValueKey('game-restart')));
    await tester.pump();
    for (var i = 0; i < 100; i++) { await tester.pump(const Duration(milliseconds: 10)); }
    expect(progress(), closeTo(tenFrames, .000001));
    await tester.pumpWidget(const SizedBox());
  });
}

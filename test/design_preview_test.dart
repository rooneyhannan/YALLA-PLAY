import 'test_fonts.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_play/main.dart';
import 'package:yalla_play/features/home/presentation/main_screen.dart';

// Opt-in visual exports for reviewing the supplied Stitch design at two sizes.
// These are review images, not automatically accepted regression baselines.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDesignFonts);
  const capture = bool.fromEnvironment('CAPTURE_PREVIEWS');
  for (final device in [
    ('mobile', const Size(390, 844)),
    ('desktop', const Size(1440, 900)),
  ]) {
    testWidgets('Export ${device.$1} design previews', skip: !capture, (
      tester,
    ) async {
      tester.view.physicalSize = device.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const YallaGuitarApp());
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(MainScreen));
      await tester.runAsync(() async {
        for (final name in [
          's1_1',
          's1_2',
          's1_3',
          's1_4',
          's1_5',
          's1_6',
          's1_7',
          's2_0',
          's2_1',
          's2_2',
          's2_3',
          's2_4',
          's2_5',
          's2_6',
          's2_7',
          's2_8',
          's2_13',
          's2_14',
          's2_15',
          's3_1',
          's3_2',
          's3_3',
          's3_4',
          's4_0',
        ]) {
          await precacheImage(AssetImage('assets/design/$name.png'), context);
        }
      });
      for (var tab = 0; tab < 4; tab++) {
        await tester.tap(find.byKey(ValueKey('nav-$tab')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MainScreen),
          matchesGoldenFile('previews/${device.$1}-$tab.png'),
        );
        if (device.$1 == 'mobile' && (tab == 0 || tab == 2)) {
          final scroll = find.byKey(
            PageStorageKey(tab == 0 ? 'dashboard' : 'songs'),
          );
          await tester.drag(scroll, const Offset(0, -620));
          await tester.pumpAndSettle();
          await expectLater(
            find.byType(MainScreen),
            matchesGoldenFile('previews/mobile-$tab-details.png'),
          );
          if (tab == 2) {
            await tester.drag(scroll, const Offset(0, -620));
            await tester.pumpAndSettle();
            await expectLater(
              find.byType(MainScreen),
              matchesGoldenFile('previews/mobile-$tab-artists.png'),
            );
          }
          await tester.drag(scroll, const Offset(0, 2500));
          await tester.pumpAndSettle();
        }
      }
      await tester.tap(find.byKey(const ValueKey('nav-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('daily-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 500));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('previews/${device.$1}-game.png'),
      );
      await tester.pumpWidget(const SizedBox());
    });
  }
}

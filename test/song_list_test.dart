import 'test_fonts.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_play/core/models/song.dart';
import 'package:yalla_play/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDesignFonts);

  test('songs with a chart come first, otherwise in their order', () {
    const a = Song(id: 'a', title: 'A', artist: '', category: '', image: '');
    const b = Song(id: 'b', title: 'B', artist: '', category: '', image: '');
    const c = Song(
      id: 'c',
      title: 'C',
      artist: '',
      category: '',
      image: '',
      chart: 'c',
    );
    const d = Song(
      id: 'd',
      title: 'D',
      artist: '',
      category: '',
      image: '',
      source: '{}',
    );
    final ids = playableFirst([a, c, b, d]).map((s) => s.id);
    expect(ids, ['c', 'd', 'a', 'b']);
    expect(playableFirst(<Song>[]), isEmpty);
  });

  testWidgets('the song list marks the songs that only play the demo', (
    tester,
  ) async {
    await tester.pumpWidget(const YallaGuitarApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('demo-note')), findsOneWidget);
    expect(find.byKey(const ValueKey('song-badak')), findsOneWidget);
    expect(find.byKey(const ValueKey('demo-badak')), findsNothing);
    expect(find.byKey(const ValueKey('demo-life')), findsOneWidget);
    // Ba’dak, the song with a chart, leads the row.
    final badak = tester.getTopLeft(find.byKey(const ValueKey('song-badak')));
    final life = tester.getTopLeft(find.byKey(const ValueKey('song-life')));
    // The app reads right to left.
    expect(badak.dx, greaterThan(life.dx));
  });
}

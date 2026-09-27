import 'dart:io';

import 'package:yalla_play/features/game/data/song_chart.dart';
import 'package:yalla_play/features/game/data/song_data.dart';

/// The chart the app ships, read the way tests can: straight from disk.
final demoChart = SongChart.parse(
  File('assets/songs/badak.json').readAsStringSync(),
);

/// Its notes, one after another.
final List<Note> rawSongData = [for (final n in demoChart.notes) n.note];

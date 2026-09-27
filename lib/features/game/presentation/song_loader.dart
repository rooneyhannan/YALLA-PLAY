import 'package:flutter/material.dart';

import '../../../core/models/song.dart';
import '../../../core/theme/app_theme.dart';
import '../data/song_chart.dart';
import 'game_screen.dart';

/// Loads a song's chart, then opens the play screen with it. Songs without
/// a chart of their own play the demo chart for illustration.
class SongLoader extends StatefulWidget {
  static const demoChart = 'badak';

  final Song song;
  const SongLoader({super.key, required this.song});
  @override
  State<SongLoader> createState() => _SongLoaderState();
}

class _SongLoaderState extends State<SongLoader> {
  late final Future<SongChart> _chart = SongChart.load(
    widget.song.chart ?? SongLoader.demoChart,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _chart,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return GameScreen(song: widget.song, chart: snapshot.data!);
      }
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: snapshot.hasError
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'تعذّر تحميل نوتة الأغنية.\n${snapshot.error}',
                    key: const ValueKey('song-load-error'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.cream),
                  ),
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}

import 'package:flutter/material.dart';

import '../../../core/models/song.dart';
import '../../game/presentation/song_loader.dart';

// Kept as a compatibility route. Song selections now open the game directly.
class SongStartScreen extends StatelessWidget {
  final Song song;
  const SongStartScreen({super.key, required this.song});
  @override
  Widget build(BuildContext context) => SongLoader(song: song);
}

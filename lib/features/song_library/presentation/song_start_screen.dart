import 'package:flutter/material.dart';
import '../../../core/models/song.dart';
import '../../game/presentation/game_screen.dart';

// Kept as a compatibility route. Song selections now open the game directly.
class SongStartScreen extends StatelessWidget {
  final Song song;
  const SongStartScreen({super.key, required this.song});
  @override
  Widget build(BuildContext context) => GameScreen(song: song);
}

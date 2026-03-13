import 'package:flutter/material.dart';
import '../../../core/models/song.dart';
import 'song_start_screen.dart';

class SongsScreen extends StatelessWidget {
  const SongsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Basic filtering
    final arabSongs = dummySongs.where((s) => 
      s.category.contains('Arab') || s.category.contains('Rai')
    ).toList();

    final globalSongs = dummySongs.where((s) => 
      !s.category.contains('Arab') && 
      !s.category.contains('Rai') && 
      !s.category.contains('Folk')
    ).toList();

    final beginnerSongs = dummySongs.where((s) => 
      s.category.contains('Folk')
    ).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20), 
            _buildSection(context, "Beliebte Arabische Songs", arabSongs),
            _buildSection(context, "Trending Global", globalSongs),
            _buildSection(context, "Für Anfänger", beginnerSongs),
            const SizedBox(height: 80), // Bottom padding for nav bar
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, List<Song> songs) {
    if (songs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
        SizedBox(
          height: 220,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: songs.length,
            separatorBuilder: (context, index) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final song = songs[index];
              return _buildSongCard(context, song);
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSongCard(BuildContext context, Song song) {
    return SizedBox(
      width: 140,
      child: GestureDetector(
        onTap: () {
          if (song.title == "Ba'dak Ala Bali") {
             // Navigate to the intermediate screen
             Navigator.push(
               context, 
               MaterialPageRoute(builder: (context) => SongStartScreen(song: song))
             );
          } else {
             // Show "Coming Soon" for everything else
             ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text("Coming Soon! Only 'Ba'dak Ala Bali' is available right now."), 
                  duration: const Duration(seconds: 1),
                  backgroundColor: Colors.grey[800],
                ),
             );
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: song.coverColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  if (song.isPremium)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'PREMIUM',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              song.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

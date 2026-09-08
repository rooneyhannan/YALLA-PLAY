import 'package:flutter/material.dart';

import '../../../core/models/song.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/design_widgets.dart';
import '../../game/presentation/game_screen.dart';
import '../../learn/presentation/learn_screen.dart';
import '../../song_library/presentation/songs_screen.dart';
import '../../tuner/presentation/tuner_screen.dart';
import 'dashboard_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selected = 0;
  final Set<String> _favorites = {};
  Song? _recent;
  static const labels = ['الرئيسية', 'تعلم', 'الأغاني', 'دوزان'];
  static const icons = [
    Icons.home_rounded,
    Icons.school_outlined,
    Icons.music_note_rounded,
    Icons.tune_rounded,
  ];

  void _openSong(Song song) {
    setState(() => _recent = song);
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => GameScreen(song: song)));
  }

  void _toggleFavorite(Song song) => setState(() {
    if (!_favorites.add(song.id)) _favorites.remove(song.id);
  });

  Widget _nav({required bool wide}) => Row(
    mainAxisSize: wide ? MainAxisSize.min : MainAxisSize.max,
    children: List.generate(4, (i) {
      final button = Semantics(
        selected: _selected == i,
        child: TextButton(
          key: ValueKey('nav-$i'),
          onPressed: () => setState(() => _selected = i),
          style: TextButton.styleFrom(
            foregroundColor: _selected == i ? AppTheme.gold : AppTheme.cream,
            minimumSize: Size(wide ? 84 : 48, 64),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icons[i], size: 25),
              const SizedBox(height: 3),
              Text(
                labels[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: _selected == i
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
      return wide ? button : Expanded(child: button);
    }),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 850;
      final pages = [
        DashboardScreen(
          onSongs: () => setState(() => _selected = 2),
          onLearn: () => setState(() => _selected = 1),
          onStart: () => _openSong(songs.first),
        ),
        LearnScreen(onPractice: () => _openSong(songs.first)),
        SongsScreen(
          onSong: _openSong,
          favorites: _favorites,
          onFavorite: _toggleFavorite,
          recent: _recent,
        ),
        TunerScreen(onBack: () => setState(() => _selected = 0)),
      ];
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (_selected != 3 || wide)
                Container(
                  height: wide ? 84 : 68,
                  decoration: const BoxDecoration(
                    color: AppTheme.background,
                    border: Border(
                      bottom: BorderSide(color: Color(0x224D4635)),
                    ),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 16),
                  child: Row(
                    textDirection: TextDirection.ltr,
                    children: [
                      InkWell(
                        onTap: () => showPreviewInfo(
                          context,
                          title: 'ملفك الشخصي',
                          message:
                              'ملفك الشخصي والإنجازات ستتوفر قريباً. استكشف الأغاني وابدأ العزف الآن.',
                        ),
                        borderRadius: BorderRadius.circular(24),
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: ClipOval(child: const DesignImage('s1_1.png')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (wide) _points(),
                      Expanded(
                        child: wide
                            ? Center(child: _nav(wide: true))
                            : const SizedBox(),
                      ),
                      const Text(
                        'Yalla Guitar',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.gold,
                        ),
                      ),
                      if (!wide) ...[const Spacer(), _points(compact: true)],
                    ],
                  ),
                ),
              Expanded(
                child: PatternBackground(
                  child: IndexedStack(index: _selected, children: pages),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : Container(
                decoration: const BoxDecoration(
                  color: AppTheme.surface,
                  border: Border(top: BorderSide(color: Color(0x554D4635))),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: _nav(wide: false),
                  ),
                ),
              ),
      );
    },
  );

  Widget _points({bool compact = false}) => Tooltip(
    message: 'معاينة النقاط من التصميم',
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 12, vertical: 6),
      decoration: BoxDecoration(
        color: compact ? Colors.transparent : AppTheme.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            compact ? '١٢٠٠' : '١٢٠٠ نقطة',
            style: const TextStyle(color: AppTheme.gold, fontSize: 13),
          ),
          const SizedBox(width: 5),
          const Icon(Icons.star_rounded, color: AppTheme.gold, size: 18),
        ],
      ),
    ),
  );
}

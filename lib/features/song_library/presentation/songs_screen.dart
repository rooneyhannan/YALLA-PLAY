import 'package:flutter/material.dart';
import '../../../core/models/song.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/design_widgets.dart';

class SongsScreen extends StatefulWidget {
  final ValueChanged<Song> onSong, onFavorite;
  final Set<String> favorites;
  final Song? recent;
  const SongsScreen({super.key, required this.onSong, required this.onFavorite, required this.favorites, this.recent});
  @override
  State<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends State<SongsScreen> {
  void _collection(String title, List<Song> entries) {
    showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(expand: false, initialChildSize: .72, maxChildSize: .9, minChildSize: .4,
        builder: (context, controller) => StatefulBuilder(builder: (context, refresh) => ListView(
          controller: controller, padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
            Text(title, style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 16),
            if (entries.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('لا توجد أغانٍ في هذا القسم بعد. استكشف مكتبة الأغاني.', textAlign: TextAlign.center)),
            for (final song in entries) Padding(padding: const EdgeInsets.only(bottom: 8), child: ListTile(
              key: ValueKey('collection-${song.id}'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              leading: SizedBox(width: 56, height: 56, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: DesignImage(song.image))),
              title: Text(song.title), subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(tooltip: 'إضافة أو إزالة من المفضلة',
                icon: Icon(widget.favorites.contains(song.id) ? Icons.favorite : Icons.favorite_border, color: AppTheme.gold),
                onPressed: () { widget.onFavorite(song); refresh(() {}); }),
              onTap: () { Navigator.pop(context); widget.onSong(song); },
            )),
          ]))));
  }

  void _search() {
    showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true,
      builder: (context) {
        var query = '';
        return StatefulBuilder(builder: (context, refresh) {
          final results = songs.where((s) => '${s.title} ${s.artist}'.toLowerCase().contains(query.toLowerCase())).toList();
          return SafeArea(child: Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 16),
            child: SizedBox(height: MediaQuery.sizeOf(context).height * .65, child: Column(children: [
              TextField(autofocus: true, decoration: const InputDecoration(hintText: 'ابحث عن أغنية أو فنان', prefixIcon: Icon(Icons.search)), onChanged: (value) => refresh(() => query = value)),
              const SizedBox(height: 16),
              Expanded(child: results.isEmpty ? const Center(child: Text('لا توجد نتائج')) : ListView(children: [for (final song in results) ListTile(
                title: Text(song.title), subtitle: Text(song.artist), trailing: const Icon(Icons.play_circle_outline, color: AppTheme.gold),
                onTap: () { Navigator.pop(context); widget.onSong(song); },
              )])),
            ]))));
        });
      });
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(key: const PageStorageKey('songs'),
    child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1280),
      child: Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 40), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Expanded(child: TrialBanner(outlined: true)),
          IconButton(key: const ValueKey('song-search'), tooltip: 'البحث', onPressed: _search, icon: const Icon(Icons.search)),
          IconButton(tooltip: 'الإعدادات', onPressed: () => showPreviewInfo(context, title: 'الإعدادات', message: 'العرض باللغة العربية، مع ضبط قياسي للغيتار. مزيد من الإعدادات قريباً.'), icon: const Icon(Icons.settings_outlined)),
        ]),
        const SizedBox(height: 24),
        LayoutBuilder(builder: (context, c) => Wrap(spacing: 16, runSpacing: 12, children: [
          SizedBox(width: c.maxWidth >= 650 ? (c.maxWidth - 16) / 2 : c.maxWidth,
            child: _quickTile('لعبت مؤخراً', image: widget.recent?.image ?? 's2_0.png', onTap: () => _collection('لعبت مؤخراً', [widget.recent ?? songs.first]))),
          SizedBox(width: c.maxWidth >= 650 ? (c.maxWidth - 16) / 2 : c.maxWidth,
            child: _quickTile('مفضلاتك', icon: Icons.add, onTap: () => _collection('مفضلاتك', widget.favorites.isEmpty ? songs : songs.where((s) => widget.favorites.contains(s.id)).toList()))),
        ])),
        const SizedBox(height: 30),
        SectionTitle('الأكثر شعبية', onAll: () => _collection('كل الأغاني', songs)),
        SizedBox(height: 250, child: ListView.separated(scrollDirection: Axis.horizontal,
          itemCount: 5, separatorBuilder: (_, _) => const SizedBox(width: 16),
          itemBuilder: (context, i) => _songCard(songs[i == 4 ? 0 : i + 1]))),
        const SizedBox(height: 30),
        const SectionTitle('الأنماط الموسيقية'),
        _tiles([
          ('طرب', 's2_5.png', '', () => _collection('طرب', songs.where((s) => s.category == 'طرب').toList())),
          ('بوب', 's2_6.png', '', () => _collection('بوب', songs.where((s) => s.category == 'بوب').toList())),
          ('كلاسيكي', 's2_7.png', '', () => _collection('كلاسيكي', songs.where((s) => s.category == 'كلاسيكي').toList())),
          ('جاز', 's2_8.png', '', () => _collection('جاز', [])),
        ]),
        const SizedBox(height: 30),
        const SectionTitle('مستويات الصعوبة'),
        _tiles([
          for (final pair in [('مبتدئ', 's2_13.png'), ('متوسط', 's2_14.png'), ('متقدم', 's2_15.png')])
            (pair.$1, pair.$2, '${songs.where((s) => s.difficulty == pair.$1).length} أغنية',
              () => _collection(pair.$1, songs.where((s) => s.difficulty == pair.$1).toList())),
        ]),
        const SizedBox(height: 30),
        const SectionTitle('الفنانون'),
        _tiles([
          for (final pair in [('كاظم الساهر', 's2_0.png'), ('عمرو دياب', 's2_1.png'), ('فيروز', 's2_2.png'), ('إريك كلابتون', 's2_3.png')])
            (pair.$1, pair.$2, '', () => _collection(pair.$1, songs.where((s) => s.artist == pair.$1).toList())),
        ]),
      ])))));

  Widget _quickTile(String title, {String? image, IconData? icon, required VoidCallback onTap}) => Material(
    color: AppTheme.card, borderRadius: BorderRadius.circular(12), clipBehavior: Clip.antiAlias,
    child: InkWell(onTap: onTap, child: SizedBox(height: 76, child: Row(children: [
      SizedBox(width: 86, height: 76, child: image != null ? DesignImage(image) : Icon(icon, color: AppTheme.cream, size: 30)),
      const SizedBox(width: 16), Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
    ]))));

  Widget _songCard(Song song) => SizedBox(width: 190, child: Material(color: Colors.transparent,
    child: InkWell(key: ValueKey('song-${song.id}'), onTap: () => widget.onSong(song), borderRadius: BorderRadius.circular(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(height: 180, child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Stack(fit: StackFit.expand, children: [
          DesignImage(song.image),
          if (song.isPremium) Positioned(top: 0, right: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: const BoxDecoration(color: AppTheme.gold, borderRadius: BorderRadius.only(bottomLeft: Radius.circular(10))),
            child: const Text('مميز+', style: TextStyle(color: Color(0xFF241A00), fontSize: 11, fontWeight: FontWeight.w700)))),
          Positioned(left: 5, bottom: 5, child: IconButton(tooltip: 'إضافة أو إزالة من المفضلة',
            style: IconButton.styleFrom(backgroundColor: Colors.black54),
            onPressed: () => widget.onFavorite(song),
            icon: Icon(widget.favorites.contains(song.id) ? Icons.favorite : Icons.favorite_border, size: 20, color: Colors.white))),
        ]))),
        const SizedBox(height: 10), Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        Text('${song.artist} • ${song.category}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppTheme.cream)),
      ]))));

  Widget _tiles(List<(String, String, String, VoidCallback)> entries) => LayoutBuilder(builder: (context, c) {
    final columns = c.maxWidth >= 850 ? entries.length : 2;
    final width = (c.maxWidth - (columns - 1) * 16) / columns;
    return Wrap(spacing: 16, runSpacing: 16, children: [for (final entry in entries)
      SizedBox(width: width, height: width.clamp(145, 230).toDouble(), child: Material(
        borderRadius: BorderRadius.circular(12), clipBehavior: Clip.antiAlias, color: AppTheme.card,
        child: InkWell(onTap: entry.$4, child: Stack(fit: StackFit.expand, children: [
          DesignImage(entry.$2),
          const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [.4, 1], colors: [Colors.transparent, Color(0xDD000000)]))),
          Positioned(bottom: 14, right: 14, left: 10, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(entry.$1, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
            if (entry.$3.isNotEmpty) Text(entry.$3, style: const TextStyle(fontSize: 12, color: AppTheme.cream)),
          ])),
        ])))),
    ]);
  });
}

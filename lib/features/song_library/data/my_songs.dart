import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/models/song.dart';
import '../../game/data/song_chart.dart';
import 'my_songs_store_stub.dart'
    if (dart.library.js_interop) 'my_songs_store_web.dart'
    as store;

/// Songs added from Yalla Studio with "In die App": kept in this browser's
/// storage, which the Studio shares with the app (both are served from the
/// same site), so they need no new release of the app.
class MySongs {
  /// The storage key: a JSON list of `yalla-song/1` songs.
  static const key = 'yalla.mySongs';

  static const category = 'أغانيّ';

  /// Changes whenever the Studio adds a song or one is removed.
  static final ValueNotifier<int> changes = _watch();

  static ValueNotifier<int> _watch() {
    final notifier = ValueNotifier(0);
    store.onChange(() => notifier.value++);
    return notifier;
  }

  static List<Song> all() => parse(store.read(key));

  /// The songs in [source]; entries that are not valid songs are left out.
  static List<Song> parse(String? source) {
    if (source == null || source.isEmpty) return const [];
    final Object? list;
    try {
      list = jsonDecode(source);
    } on FormatException {
      return const [];
    }
    if (list is! List) return const [];
    final songs = <Song>[];
    for (final entry in list) {
      if (entry is! Map<String, dynamic>) continue;
      final SongChart chart;
      try {
        chart = SongChart.fromJson(entry);
      } on FormatException {
        continue;
      }
      songs.add(
        Song(
          id: 'mine-${chart.id}',
          title: chart.title.isEmpty ? chart.id : chart.title,
          artist: chart.artist,
          category: category,
          image: 's1_2.png',
          source: jsonEncode(entry),
        ),
      );
    }
    return songs;
  }

  /// Removes the song with this app [id] from the device.
  static void remove(String id) {
    final source = store.read(key);
    if (source == null) return;
    final list = jsonDecode(source);
    if (list is! List) return;
    list.removeWhere((e) => e is Map && 'mine-${e['id']}' == id);
    store.write(key, jsonEncode(list));
    changes.value++;
  }
}

import 'dart:convert';

import 'package:flutter/services.dart';

import 'song_data.dart';

/// A note of a chart: when it starts, in ticks, and what to play.
class ChartNote {
  final int tick;
  final Note note;

  /// Finger of the fretting hand when the chart gives one: 1 index …
  /// 4 pinky, 0 open string. Otherwise the app works it out.
  final int? finger;
  const ChartNote(this.tick, this.note, {this.finger});
}

/// A song's notes as Yalla Studio writes them: a `yalla-song/1` JSON file
/// in assets/songs/. See docs/song-format.md.
class SongChart {
  static const format = 'yalla-song/1';

  final String id, title, artist;
  final double bpm;

  /// Ticks are the smallest step of the song: [ticksPerBeat] of them make
  /// a beat, [beatsPerBar] beats a bar.
  final int ticksPerBeat, beatsPerBar;

  /// Ordered by tick.
  final List<ChartNote> notes;

  const SongChart({
    required this.id,
    required this.title,
    required this.artist,
    required this.bpm,
    required this.notes,
    this.ticksPerBeat = 4,
    this.beatsPerBar = 4,
  });

  /// Song ticks per second at normal speed.
  double get ticksPerSecond => bpm * ticksPerBeat / 60;

  /// Parses a chart, or throws a [FormatException] naming what is wrong.
  factory SongChart.fromJson(Map<String, dynamic> json) {
    T field<T>(Map<String, dynamic> map, String key, [T? fallback]) {
      final value = map[key] ?? fallback;
      if (value is! T) {
        throw FormatException('"$key" is missing or not a ${T.toString()}');
      }
      return value;
    }

    if (json['format'] != format) {
      throw FormatException('Not a $format file: ${json['format']}');
    }
    final notes = <ChartNote>[];
    for (final (i, raw) in field<List<dynamic>>(json, 'notes').indexed) {
      if (raw is! Map<String, dynamic>) {
        throw FormatException('Note ${i + 1} is not an object');
      }
      final s = field<int>(raw, 's'), f = field<int>(raw, 'f');
      final d = field<int>(raw, 'd');
      if (s < 1 || s > 6 || f < 0 || f > 24 || d < 1) {
        throw FormatException('Note ${i + 1} is out of range: $raw');
      }
      final finger = raw['finger'];
      if (finger != null && (finger is! int || finger < 0 || finger > 4)) {
        throw FormatException('Note ${i + 1} has an invalid finger: $finger');
      }
      notes.add(
        ChartNote(field<int>(raw, 't'), Note(s, f, d), finger: finger as int?),
      );
    }
    if (notes.isEmpty) throw const FormatException('The song has no notes');
    notes.sort((a, b) => a.tick.compareTo(b.tick));
    return SongChart(
      id: field<String>(json, 'id'),
      title: field<String>(json, 'title'),
      artist: field<String>(json, 'artist', ''),
      bpm: field<num>(json, 'bpm').toDouble(),
      ticksPerBeat: field<int>(json, 'ticksPerBeat', 4),
      beatsPerBar: field<int>(json, 'beatsPerBar', 4),
      notes: notes,
    );
  }

  static SongChart parse(String source) =>
      SongChart.fromJson(jsonDecode(source) as Map<String, dynamic>);

  /// Loads the chart `assets/songs/[id].json`. Read afresh each time: it
  /// is small, and a chart edited in the Studio shows on the next open.
  static Future<SongChart> load(String id, {AssetBundle? bundle}) async =>
      parse(
        await (bundle ?? rootBundle).loadString(
          'assets/songs/$id.json',
          cache: false,
        ),
      );
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_play/features/game/data/song_chart.dart';
import 'package:yalla_play/features/song_library/data/my_songs.dart';

Map<String, Object> _song(String id, {String title = 'Jingle Bells'}) => {
  'format': 'yalla-song/1',
  'id': id,
  'title': title,
  'artist': 'Ich',
  'bpm': 110,
  'ticksPerBeat': 4,
  'beatsPerBar': 4,
  'notes': [
    {'t': 0, 's': 1, 'f': 0, 'd': 4},
    {'t': 4, 's': 1, 'f': 3, 'd': 8, 'finger': 3},
  ],
};

void main() {
  test('songs from the Studio become library songs that play their chart', () {
    final mine = MySongs.parse(
      jsonEncode([_song('jingle'), _song('ode', title: 'Ode')]),
    );
    expect(mine.map((s) => s.id), ['mine-jingle', 'mine-ode']);
    final song = mine.first;
    expect(song.title, 'Jingle Bells');
    expect(song.artist, 'Ich');
    expect(song.category, MySongs.category);
    expect(song.hasChart, isTrue);
    final chart = SongChart.parse(song.source!);
    expect(chart.notes.length, 2);
    expect(chart.notes.last.finger, 3);
    expect(chart.bpm, 110);
  });

  test('nothing stored, broken storage and broken songs are left out', () {
    expect(MySongs.parse(null), isEmpty);
    expect(MySongs.parse(''), isEmpty);
    expect(MySongs.parse('{not json'), isEmpty);
    expect(MySongs.parse('{"a": 1}'), isEmpty);
    final broken = {..._song('broken'), 'notes': <Object>[]};
    expect(
      MySongs.parse(jsonEncode([broken, 'text', _song('ok')])).map((s) => s.id),
      ['mine-ok'],
    );
  });
}

import 'package:flutter/material.dart';

class Note {
  final int s; // string (1-6)
  final int f; // fret
  final int d; // duration

  const Note(this.s, this.f, this.d);
}

// Full song data from JS reference
final List<Note> rawSongData = const [
  Note(2, 3, 4), Note(1, 5, 4), Note(1, 6, 2), Note(1, 5, 2), Note(1, 8, 4), Note(1, 5, 16),
  Note(1, 6, 4), Note(1, 5, 2), Note(1, 6, 2), Note(1, 8, 4), Note(1, 6, 2), Note(1, 5, 2),
  Note(1, 3, 16), Note(1, 5, 4), Note(1, 3, 2), Note(1, 5, 2), Note(1, 6, 4), Note(1, 5, 2),
  Note(1, 3, 2), Note(1, 1, 16), Note(1, 3, 4), Note(1, 1, 2), Note(1, 3, 2), Note(1, 5, 4),
  Note(1, 3, 2), Note(1, 1, 2), Note(1, 0, 16), Note(1, 1, 4), Note(2, 3, 4), Note(1, 6, 2),
  Note(1, 5, 2), Note(1, 8, 4), Note(1, 5, 16), Note(1, 1, 4), Note(1, 10, 2), Note(1, 10, 2),
  Note(1, 8, 2), Note(1, 6, 2), Note(1, 5, 2), Note(1, 6, 2), Note(1, 8, 16), Note(1, 8, 4),
  Note(1, 10, 2), Note(1, 8, 2), Note(1, 6, 2), Note(1, 5, 2), Note(1, 3, 2), Note(1, 5, 2),
  Note(1, 6, 8), Note(1, 10, 8), Note(1, 8, 2), Note(1, 6, 2), Note(1, 5, 4), Note(1, 3, 4),
  Note(1, 1, 2), Note(1, 0, 2), Note(2, 3, 16)
];

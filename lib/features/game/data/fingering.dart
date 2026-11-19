import 'song_data.dart';

/// What one shift costs: more than all other preferences of a song.
const _shiftCost = 1e6;

/// A shift with the pinky counts as two and a half shifts: it is only taken
/// where every other way needs at least three shifts instead.
const _pinkyShiftCost = 2.5e6;

/// Which finger slides at a shift, after the count: 1, else 3, else 2.
const _slideCost = [0.0, 0.0, 60.0, 30.0];

/// Per fret the hand moves at a shift: short slides, not jumps.
const _fretCost = 10.0;

/// A shift straight after another one.
const _againCost = 5.0;

/// Per note and fret of the hand's position: lower positions.
const _positionCost = .05;

/// Which finger of the fretting hand plays each note: 1 index … 4 pinky,
/// 0 for an open string.
///
/// Tabs only say string and fret, so the fingers follow the "one finger
/// per fret" rule: the hand sits in a position with the index at fret p
/// and fingers 1–4 over frets p to p+3. Rooney's rules, in this order:
/// 1. Every shift (position change) is made with the same finger: the
///    finger that plays the note before it slides to the next note. So the
///    hand moves exactly as far as the melody.
/// 2. As few shifts as possible.
/// 3. The sliding finger is the index (1), else the ring finger (3), else
///    the middle finger (2). The pinky (4) only when nothing else works: a
///    pinky shift counts as two and a half shifts.
/// After that: short slides rather than jumps, not straight after another
/// shift, lower positions. Notes on open strings leave the hand where it is.
///
/// The tab stays as it is. Yalla Studio uses the same rule
/// (`assignFingers` in studio/transcribe.js); its `fingerTab` also moves
/// notes to another string where that saves shifts, and the song files are
/// tabbed that way.
List<int> assignFingers(List<Note> notes) {
  // A state is the hand's position p, the finger k of the last fretted note
  // and whether it just shifted: key (p * 5 + k) * 2 + shifted; -1 before
  // the first fretted note.
  var cost = <int, double>{-1: 0};
  final back = <Map<int, (int, int)>>[];
  for (final note in notes) {
    final next = <int, double>{};
    final from = <int, (int, int)>{};
    void put(int key, double c, int before, int finger) {
      if (c < (next[key] ?? double.infinity)) {
        next[key] = c;
        from[key] = (before, finger);
      }
    }

    for (final MapEntry(key: key, value: c) in cost.entries) {
      if (note.f == 0) {
        put(key, c, key, 0);
        continue;
      }
      for (var k = 1; k <= 4; k++) {
        final p = note.f - k + 1;
        if (p < 1) break;
        final own = c + p * _positionCost;
        final to = (p * 5 + k) * 2;
        if (key < 0) {
          put(to, own, key, k);
          continue;
        }
        final q = key ~/ 10, last = (key ~/ 2) % 5, shifted = key % 2 == 1;
        if (p == q) {
          put(to, own, key, k);
          continue;
        }
        // Rule 1: the same finger slides along.
        if (k != last) continue;
        final shift =
            (k == 4 ? _pinkyShiftCost : _shiftCost + _slideCost[k]) +
            _fretCost * (p - q).abs() +
            (shifted ? _againCost : 0);
        put(to + 1, own + shift, key, k);
      }
    }
    back.add(from);
    cost = next;
  }

  int? state;
  for (final MapEntry(key: k, value: c) in cost.entries) {
    if (state == null || c < cost[state]!) state = k;
  }
  final fingers = List.filled(notes.length, 0);
  for (var i = notes.length - 1; i >= 0; i--) {
    final (before, finger) = back[i][state]!;
    fingers[i] = finger;
    state = before;
  }
  return fingers;
}

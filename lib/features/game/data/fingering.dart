import 'song_data.dart';

/// What one shift costs: more than all other preferences of a song.
const _shiftCost = 1e6;

/// Which finger of the fretting hand plays each note: 1 index … 4 pinky,
/// 0 for an open string.
///
/// Tabs only say string and fret, so the fingers follow the "one finger
/// per fret" rule: the hand sits in a position with the index at fret p
/// and fingers 1–4 over frets p to p+3. Rooney's rules, in this order:
/// 1. As few shifts (position changes) as possible.
/// 2. A shift never goes against the fingers: moving up the neck the next
///    finger is never a lower one (not 3 on fret 5, then 2 on fret 8),
///    moving down never a higher one (not 1, then 3). So the hand moves
///    with the melody and never further than it does. This one is never
///    broken; a shift that keeps it is always possible.
/// 3. Ideally the same finger slides along (hand and melody move alike).
/// After that: not straight after another shift, a shift over an open
/// string (the hand is free there), short moves, lower positions.
///
/// Yalla Studio uses the same rule (`assignFingers` in studio/transcribe.js).
List<int> assignFingers(List<Note> notes) {
  const maxPosition = 21, inf = double.infinity;
  bool fits(int position, int fret) =>
      fret >= position && fret <= position + 3;

  final fretted = [
    for (var i = 0; i < notes.length; i++)
      if (notes[i].f > 0) i,
  ];
  final positions = List.filled(notes.length, 0);

  if (fretted.isNotEmpty) {
    double shift(int q, int p, int from, int to, bool free, bool shifted) {
      if (p == q) return 0;
      final hand = p - q, step = to - from;
      // Rule 2: with the melody and never further than it.
      if (step.sign != hand.sign || hand.abs() > step.abs()) return inf;
      // Rule 1 outweighs everything else; then rule 3 (how much the finger
      // changes) and the gentler preferences.
      final fingerChange = (step - hand).abs();
      final detail = .05 * hand.abs() + fingerChange + (shifted ? .8 : 0);
      return _shiftCost + (free ? detail / 2 : detail);
    }

    // States 2p (hand in position p) and 2p + 1 (just shifted there);
    // cost[s]: cheapest way to play the notes so far ending in state s.
    const states = 2 * (maxPosition + 1);
    var cost = List.filled(states, inf);
    for (var p = 1; p <= maxPosition; p++) {
      if (fits(p, notes[fretted.first].f)) cost[2 * p] = p * .001;
    }
    final from = <List<int>>[];
    for (var k = 1; k < fretted.length; k++) {
      final a = fretted[k - 1], b = fretted[k];
      final free = b - a > 1;
      final next = List.filled(states, inf);
      final back = List.filled(states, 0);
      for (var p = 1; p <= maxPosition; p++) {
        if (!fits(p, notes[b].f)) continue;
        for (var s = 2; s < states; s++) {
          if (cost[s] == inf) continue;
          final q = s >> 1, to = 2 * p + (p == q ? 0 : 1);
          final total =
              cost[s] +
              shift(q, p, notes[a].f, notes[b].f, free, s % 2 == 1) +
              p * .001;
          if (total < next[to]) {
            next[to] = total;
            back[to] = s;
          }
        }
      }
      from.add(back);
      cost = next;
    }

    var state = 2;
    for (var t = 2; t < states; t++) {
      if (cost[t] < cost[state]) state = t;
    }
    for (var k = fretted.length - 1; k >= 0; k--) {
      positions[fretted[k]] = state >> 1;
      if (k > 0) state = from[k - 1][state];
    }
  }
  return [
    for (var i = 0; i < notes.length; i++)
      notes[i].f == 0 ? 0 : notes[i].f - positions[i] + 1,
  ];
}

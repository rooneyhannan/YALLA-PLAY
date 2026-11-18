import 'song_data.dart';

/// Which finger of the fretting hand plays each note: 1 index … 4 pinky,
/// 0 for an open string.
///
/// Tabs only say string and fret, so the fingers follow the "one finger
/// per fret" rule: the hand sits in a position with the index at fret p
/// and fingers 1–4 over frets p to p+3. The positions are chosen for the
/// fewest and most natural shifts over the whole song, lower positions
/// first. A natural shift moves the hand with the melody and about as far
/// as it does (ideally one finger slides along), never against it or far
/// for a small step (pinky on fret 5, then index on fret 6), and not
/// straight after another shift. An open string in between frees the hand,
/// so shifting there is cheaper.
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
      // Finger change = how much further the hand moves than the melody.
      final fingerChange = (step - hand).abs();
      final against = step == 0 || step.sign != hand.sign;
      final cost =
          1 +
          .05 * hand.abs() +
          .4 * fingerChange +
          (fingerChange > 1 ? fingerChange - 1 : 0) +
          (against ? 1.5 : 0) +
          (shifted ? .8 : 0);
      return free ? cost / 2 : cost;
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

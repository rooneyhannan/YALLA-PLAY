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
/// for a small step (pinky on fret 5, then index on fret 6). An open string
/// in between frees the hand, so shifting there is cheaper.
///
/// Yalla Studio uses the same rule (`assignFingers` in studio/transcribe.js).
List<int> assignFingers(List<Note> notes) {
  const maxPosition = 20, inf = double.infinity;
  bool fits(int position, int fret) =>
      fret >= position && fret <= position + 3;

  final fretted = [
    for (var i = 0; i < notes.length; i++)
      if (notes[i].f > 0) i,
  ];
  final positions = List.filled(notes.length, 0);

  if (fretted.isNotEmpty) {
    double shift(int q, int p, int from, int to, bool free) {
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
          (against ? 1.5 : 0);
      return free ? cost / 2 : cost;
    }

    // cost[p]: cheapest way to play the notes so far ending in position p.
    var cost = [
      for (var p = 0; p <= maxPosition; p++)
        p > 0 && fits(p, notes[fretted.first].f) ? p * .001 : inf,
    ];
    final from = <List<int>>[];
    for (var k = 1; k < fretted.length; k++) {
      final a = fretted[k - 1], b = fretted[k];
      final free = b - a > 1;
      final next = List.filled(maxPosition + 1, inf);
      final back = List.filled(maxPosition + 1, 0);
      for (var p = 1; p <= maxPosition; p++) {
        if (!fits(p, notes[b].f)) continue;
        for (var q = 1; q <= maxPosition; q++) {
          if (cost[q] == inf) continue;
          final total =
              cost[q] + shift(q, p, notes[a].f, notes[b].f, free) + p * .001;
          if (total < next[p]) {
            next[p] = total;
            back[p] = q;
          }
        }
      }
      from.add(back);
      cost = next;
    }

    var position = 1;
    for (var p = 1; p <= maxPosition; p++) {
      if (cost[p] < cost[position]) position = p;
    }
    for (var k = fretted.length - 1; k >= 0; k--) {
      positions[fretted[k]] = position;
      if (k > 0) position = from[k - 1][position];
    }
  }
  return [
    for (var i = 0; i < notes.length; i++)
      notes[i].f == 0 ? 0 : notes[i].f - positions[i] + 1,
  ];
}

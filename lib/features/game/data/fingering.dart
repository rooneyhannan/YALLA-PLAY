import 'song_data.dart';

/// Which finger of the fretting hand plays each note: 1 index … 4 pinky,
/// 0 for an open string.
///
/// Tabs only say string and fret, so the fingers follow the "one finger
/// per fret" rule: the hand sits in a position with the index at fret p
/// and fingers 1–4 over frets p to p+3. The positions are chosen for the
/// fewest and shortest shifts over the whole song, lower positions first.
List<int> assignFingers(List<Note> notes) {
  const maxPosition = 20, inf = double.infinity;
  bool fits(int position, int fret) =>
      fret == 0 || (fret >= position && fret <= position + 3);

  // cost[p]: cheapest way to play the notes so far ending in position p.
  var cost = [
    for (var p = 0; p <= maxPosition; p++)
      p == 0 ? inf : (notes.isEmpty || fits(p, notes.first.f) ? p * .001 : inf),
  ];
  final from = <List<int>>[];
  for (var i = 1; i < notes.length; i++) {
    final next = List.filled(maxPosition + 1, inf);
    final back = List.filled(maxPosition + 1, 0);
    for (var p = 1; p <= maxPosition; p++) {
      if (!fits(p, notes[i].f)) continue;
      for (var q = 1; q <= maxPosition; q++) {
        if (cost[q] == inf) continue;
        final shift = p == q ? 0 : 1 + .05 * (p - q).abs();
        final total = cost[q] + shift + p * .001;
        if (total < next[p]) {
          next[p] = total;
          back[p] = q;
        }
      }
    }
    from.add(back);
    cost = next;
  }
  if (notes.isEmpty) return [];

  var position = 1;
  for (var p = 1; p <= maxPosition; p++) {
    if (cost[p] < cost[position]) position = p;
  }
  final positions = List.filled(notes.length, 1);
  for (var i = notes.length - 1; i >= 0; i--) {
    positions[i] = position;
    if (i > 0) position = from[i - 1][position];
  }
  return [
    for (var i = 0; i < notes.length; i++)
      notes[i].f == 0 ? 0 : notes[i].f - positions[i] + 1,
  ];
}

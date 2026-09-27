/// A chord as musicians write it: `C`, `Dm`, `A7`, `Gmaj7`, `Bb`, `F#m7`,
/// `Esus4`, `C/E` (C with E in the bass) and so on.
class ChordSymbol {
  final String name;

  /// Pitch class of the root, 0 = C … 11 = B.
  final int root;

  /// Semitones above the root, the root itself (0) first.
  final List<int> intervals;

  /// Pitch class of the bass note, when it is not the root (`C/E`).
  final int? bass;

  const ChordSymbol(this.name, this.root, this.intervals, {this.bass});

  /// A plain major or minor triad.
  factory ChordSymbol.triad(int root, {required bool minor}) {
    final name = '${_names[root]}${minor ? 'm' : ''}';
    return ChordSymbol(name, root, minor ? const [0, 3, 7] : const [0, 4, 7]);
  }

  /// Chord types by suffix, as the Studio offers them. The same table is in
  /// studio/transcribe.js.
  static const qualities = <String, List<int>>{
    '': [0, 4, 7],
    'm': [0, 3, 7],
    '7': [0, 4, 7, 10],
    'maj7': [0, 4, 7, 11],
    'm7': [0, 3, 7, 10],
    '6': [0, 4, 7, 9],
    'm6': [0, 3, 7, 9],
    'dim': [0, 3, 6],
    'aug': [0, 4, 8],
    'sus2': [0, 2, 7],
    'sus4': [0, 5, 7],
    'add9': [0, 4, 7, 14],
    '9': [0, 4, 7, 10, 14],
    '5': [0, 7],
  };

  static const _names = [
    'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B', //
  ];
  static const _letters = {
    'C': 0,
    'D': 2,
    'E': 4,
    'F': 5,
    'G': 7,
    'A': 9,
    'B': 11,
  };
  static final _pattern = RegExp(
    r'^([A-G])([#b]?)([a-z0-9]*)(?:/([A-G])([#b]?))?$',
  );

  static int _pitch(String letter, String accidental) =>
      (_letters[letter]! +
          (accidental == '#'
              ? 1
              : accidental == 'b'
              ? -1
              : 0)) %
      12;

  /// Reads a chord name, or returns null when it is not one.
  static ChordSymbol? tryParse(String name) {
    final m = _pattern.firstMatch(name.trim());
    if (m == null) return null;
    final intervals = qualities[m[3]!];
    if (intervals == null) return null;
    final root = _pitch(m[1]!, m[2]!);
    final bass = m[4] == null ? null : _pitch(m[4]!, m[5]!);
    return ChordSymbol(
      name.trim(),
      root,
      intervals,
      bass: bass == root ? null : bass,
    );
  }

  /// The pitch classes the chord is made of.
  Set<int> get tones => {for (final i in intervals) (root + i) % 12};

  /// The note the bass plays: the slash note, else the root.
  int get bassNote => bass ?? root;

  bool get isTriad => intervals.length == 3 && intervals[2] == 7;
  bool get isMinor => intervals.length > 1 && intervals[1] == 3;

  @override
  bool operator ==(Object other) =>
      other is ChordSymbol &&
      other.root == root &&
      other.bass == bass &&
      other.intervals.join(',') == intervals.join(',');

  @override
  int get hashCode => Object.hash(root, bass, intervals.join(','));

  @override
  String toString() => name;
}

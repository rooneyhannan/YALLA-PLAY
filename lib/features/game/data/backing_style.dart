/// What the accompanying guitars play: one strums, the other picks the
/// chord note by note.
enum BackingGuitar {
  /// Both at once.
  both,
  strum,
  arpeggio,

  /// No guitars; bass, strings and darbuka still play.
  off,
}

/// The Arabic rhythm the strumming guitar and the darbuka follow.
enum BackingRhythm {
  /// By the song's metre: Maqsum in 4/4, Sama'i in 10/8, a plain one
  /// otherwise.
  auto,
  maqsum,
  baladi,
  saidi,
  wahda,
  samai,
}

/// How a song wants its backing played, as Yalla Studio sets it: the
/// `backing` object of a `yalla-song/1` file. See docs/song-format.md.
class BackingStyle {
  final BackingGuitar guitar;
  final BackingRhythm rhythm;

  /// Whether a darbuka plays the rhythm.
  final bool darbuka;

  const BackingStyle({
    this.guitar = BackingGuitar.both,
    this.rhythm = BackingRhythm.auto,
    this.darbuka = true,
  });

  /// Reads the `backing` object, or throws a [FormatException] naming
  /// what is wrong. Missing fields keep their defaults.
  factory BackingStyle.fromJson(Object? json) {
    if (json == null) return const BackingStyle();
    if (json is! Map<String, dynamic>) {
      throw const FormatException('"backing" is not an object');
    }
    T pick<T extends Enum>(List<T> values, String key, T fallback) {
      final name = json[key];
      if (name == null) return fallback;
      for (final v in values) {
        if (v.name == name) return v;
      }
      throw FormatException('Unknown backing $key "$name"');
    }

    final darbuka = json['darbuka'] ?? true;
    if (darbuka is! bool) {
      throw FormatException('"darbuka" is not true or false: $darbuka');
    }
    return BackingStyle(
      guitar: pick(BackingGuitar.values, 'guitar', BackingGuitar.both),
      rhythm: pick(BackingRhythm.values, 'rhythm', BackingRhythm.auto),
      darbuka: darbuka,
    );
  }

  /// The rhythm over a bar of [steps] steps, one letter a step: `D` doum,
  /// the deep stroke in the middle of the drum, `T` tek, the bright one on
  /// its rim, `k` ka, a soft tek filling in between. A named rhythm that
  /// does not fit the bar gives way to the plain one.
  static String pattern(BackingRhythm rhythm, int steps) {
    final named = switch (rhythm) {
      BackingRhythm.maqsum => 'DTkTDkTk',
      BackingRhythm.baladi => 'DDkTDkTk',
      BackingRhythm.saidi => 'DTkDDkTk',
      BackingRhythm.wahda => 'DkkTkkTk',
      BackingRhythm.samai => 'DkkTkDDkTk',
      BackingRhythm.auto => switch (steps) {
        8 => 'DTkTDkTk',
        10 => 'DkkTkDDkTk',
        4 => 'DkDT',
        6 => 'DkTkTk',
        _ => '',
      },
    };
    if (named.length == steps) return named;
    // Plain: doum on the one, tek on every other even step, ka between.
    return [
      for (var i = 0; i < steps; i++) i == 0 ? 'D' : (i.isEven ? 'T' : 'k'),
    ].join();
  }
}

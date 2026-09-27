import 'dart:math' as math;

import 'chord_symbol.dart';
import 'synth.dart';

/// One sound at a point of the song, in ticks.
class SoundEvent {
  final double tick;
  final Voice voice;
  final double frequency;

  /// How long it sounds, in ticks.
  final double length;
  final double gain;
  const SoundEvent(
    this.tick,
    this.voice,
    this.frequency,
    this.length,
    this.gain,
  );
}

/// A melody note: when it starts, how long it lasts, both in ticks, and
/// its pitch.
typedef MelodyNote = ({double start, double length, double frequency});

/// Pitch class, 0 = C … 11 = B.
int pitchClass(double frequency) =>
    (12 * math.log(frequency / 440) / math.ln2 + 69).round() % 12;

double _midiFrequency(int midi) =>
    440 * math.pow(2, (midi - 69) / 12).toDouble();

/// A chord of the song's backing: when it starts and how long it lasts, in
/// ticks.
typedef ChordSpan = ({double start, double length, ChordSymbol chord});

/// Everything the song plays besides the player: metronome, backing chords
/// and the melody itself.
///
/// The backing never sounds the pitch the player is asked for at that
/// moment, in any octave: the microphone listens for exactly that pitch,
/// and it must come from the guitar, not from the phone's speaker.
class Arrangement {
  /// All events, ordered by tick.
  final List<SoundEvent> events;

  /// The chords the backing plays: the song's own, or, when it has none,
  /// one chosen for each half bar.
  final List<ChordSpan> chords;
  const Arrangement._(this.events, this.chords);

  /// A pitch counts as asked for from this long before its note until this
  /// long after its start, in seconds: the early and late windows, with
  /// some margin.
  static const _askedBefore = .33, _askedAfter = .5;

  factory Arrangement.of(
    List<MelodyNote> melody, {
    required double firstBeat,
    required double end,
    double beatTicks = 4,
    double barTicks = 16,
    double ticksPerSecond = 6,
    List<ChordSpan>? chords,
  }) {
    final halfBar = barTicks / 2;
    final askedBefore = _askedBefore * ticksPerSecond;
    final askedAfter = _askedAfter * ticksPerSecond;
    final events = <SoundEvent>[];
    // Metronome on every beat, stressed on the first beat of each bar.
    for (
      var t = firstBeat - (firstBeat ~/ beatTicks) * beatTicks;
      t < end;
      t += beatTicks
    ) {
      final accent = (t - firstBeat) % barTicks == 0;
      events.add(SoundEvent(t, accent ? Voice.accent : Voice.click, 0, 1, 1));
    }

    final given = chords != null && chords.isNotEmpty;
    final spans = given
        ? ([...chords]..sort((a, b) => a.start.compareTo(b.start)))
        : [
            for (final (i, c) in _harmonize(melody, firstBeat, halfBar).indexed)
              (start: firstBeat + i * halfBar, length: halfBar, chord: c),
          ];
    final last = math.max(
      melody.isEmpty
          ? firstBeat
          : melody.map((n) => n.start + n.length).reduce(math.max),
      given ? spans.map((c) => c.start + c.length).reduce(math.max) : 0.0,
    );
    Set<int> asked(double from, double to) => {
      for (final n in melody)
        if (n.start - askedBefore < to &&
            n.start + math.max(n.length, askedAfter) > from)
          pitchClass(n.frequency),
    };
    // The chord sounding at a tick; none in the gaps between given chords.
    ChordSymbol? chordAt(double t) {
      for (final c in spans.reversed) {
        if (c.start <= t + 1e-6) {
          return t < c.start + c.length - 1e-6 || !given ? c.chord : null;
        }
      }
      return given ? null : spans.first.chord;
    }

    // Soft chords on every beat, a bass note every half bar.
    for (var t = firstBeat; t < last; t += beatTicks) {
      final chord = chordAt(t);
      if (chord == null) continue;
      final avoid = asked(t, t + beatTicks);
      // Between G3 and F#4: under and around the melody.
      final voicing = [
        for (final pc in chord.tones)
          if (!avoid.contains(pc)) 55 + (pc - 55) % 12,
      ];
      // A tone left out for the player is made up so the chord stays full:
      // a chosen triad by its seventh, any chord by doubling a tone an
      // octave up.
      final seventh = (chord.root + (chord.isMinor ? 10 : 11)) % 12;
      if (!given && voicing.length < 3 && !avoid.contains(seventh)) {
        voicing.add(55 + (seventh - 55) % 12);
      }
      if (voicing.length < 3 && voicing.isNotEmpty) {
        voicing.add(voicing.reduce(math.min) + 12);
      }
      for (final midi in voicing) {
        events.add(
          SoundEvent(t, Voice.chord, _midiFrequency(midi), beatTicks, .16),
        );
      }
      if ((t - firstBeat) % halfBar == 0) {
        final avoidBass = asked(t, t + halfBar);
        // The bass note of the chord, else its fifth or another tone of it.
        final pc = [
          chord.bassNote,
          (chord.root + 7) % 12,
          ...chord.tones,
        ].where((pc) => !avoidBass.contains(pc)).firstOrNull;
        if (pc != null) {
          // Between E2 and D#3, below the guitar's melody.
          final midi = 40 + (pc - 40) % 12;
          events.add(
            SoundEvent(t, Voice.bass, _midiFrequency(midi), halfBar, .3),
          );
        }
      }
    }

    for (final n in melody) {
      events.add(SoundEvent(n.start, Voice.guitar, n.frequency, n.length, .5));
    }
    events.sort((a, b) => a.tick.compareTo(b.tick));
    return Arrangement._(events, spans);
  }

  /// Picks a chord for every half bar: the triad of the song's key that
  /// holds most of the melody sounding in it, staying on the chord before
  /// when that fits as well.
  static List<ChordSymbol> _harmonize(
    List<MelodyNote> melody,
    double firstBeat,
    double halfBar,
  ) {
    if (melody.isEmpty) return [ChordSymbol.triad(0, minor: false)];
    final key = _key(melody);
    final scale = key.minor
        ? const [0, 2, 3, 5, 7, 8, 10]
        : const [0, 2, 4, 5, 7, 9, 11];
    final candidates = <ChordSymbol>[
      for (var degree = 0; degree < 7; degree++)
        // Diminished triads are left out; they rarely carry a melody.
        if ((scale[(degree + 4) % 7] - scale[degree]) % 12 == 7)
          ChordSymbol.triad(
            (key.tonic + scale[degree]) % 12,
            minor: (scale[(degree + 2) % 7] - scale[degree]) % 12 == 3,
          ),
      // The major dominant of minor keys.
      if (key.minor) ChordSymbol.triad((key.tonic + 7) % 12, minor: false),
    ];

    final end = melody.map((n) => n.start + n.length).reduce(math.max);
    final count = math.max(1, ((end - firstBeat) / halfBar).ceil());
    final chords = <ChordSymbol>[];
    var previous = ChordSymbol.triad(key.tonic, minor: key.minor);
    for (var i = 0; i < count; i++) {
      final from = firstBeat + i * halfBar, to = from + halfBar;
      final weight = List.filled(12, 0.0);
      for (final n in melody) {
        final overlap =
            math.min(to, n.start + n.length) - math.max(from, n.start);
        if (overlap > 0) weight[pitchClass(n.frequency)] += overlap;
      }
      final total = weight.reduce((a, b) => a + b);
      if (total == 0) {
        chords.add(previous);
        continue;
      }
      double score(ChordSymbol c) {
        final tones = c.tones;
        var s = 0.0;
        for (var pc = 0; pc < 12; pc++) {
          s += tones.contains(pc) ? weight[pc] : -.5 * weight[pc];
        }
        if (c == previous) s += .15 * total;
        if (c.root == key.tonic) s += .05 * total;
        return s;
      }

      previous = candidates.reduce((a, b) => score(b) > score(a) ? b : a);
      chords.add(previous);
    }
    return chords;
  }

  /// The key of the melody, by the Krumhansl-Schmuckler profiles.
  static ({int tonic, bool minor}) _key(List<MelodyNote> melody) {
    const major = [
      6.35,
      2.23,
      3.48,
      2.33,
      4.38,
      4.09,
      2.52,
      5.19,
      2.39,
      3.66,
      2.29,
      2.88,
    ];
    const minor = [
      6.33,
      2.68,
      3.52,
      5.38,
      2.60,
      3.53,
      2.54,
      4.75,
      3.98,
      2.69,
      3.34,
      3.17,
    ];
    final weight = List.filled(12, 0.0);
    for (final n in melody) {
      weight[pitchClass(n.frequency)] += n.length;
    }
    var best = (tonic: 0, minor: false);
    var bestScore = double.negativeInfinity;
    for (var tonic = 0; tonic < 12; tonic++) {
      for (final isMinor in [false, true]) {
        final profile = isMinor ? minor : major;
        var s = 0.0;
        for (var pc = 0; pc < 12; pc++) {
          s += weight[pc] * profile[(pc - tonic) % 12];
        }
        if (s > bestScore) {
          bestScore = s;
          best = (tonic: tonic, minor: isMinor);
        }
      }
    }
    return best;
  }
}

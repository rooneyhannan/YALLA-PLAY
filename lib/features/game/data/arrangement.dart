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
  /// one chosen for each bar.
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
    final chosen = given
        ? const <ChordSymbol>[]
        : _harmonize(melody, firstBeat, barTicks);
    final spans = given
        ? ([...chords]..sort((a, b) => a.start.compareTo(b.start)))
        : [
            for (final (i, c) in chosen.indexed)
              (start: firstBeat + i * barTicks, length: barTicks, chord: c),
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

    // The span sounding at a tick, with where it ends; none in the gaps
    // between given chords.
    ({ChordSymbol chord, double end})? spanAt(double t) {
      final chord = chordAt(t);
      if (chord == null) return null;
      final span = spans.lastWhere(
        (c) => c.start <= t + 1e-6,
        orElse: () => spans.first,
      );
      final end = span.start + span.length;
      // Chosen chords last a bar each; the last one carries on to the end.
      return (chord: chord, end: !given && t >= end - 1e-6 ? last : end);
    }

    // The backing moves on a grid of eighths in 4/4 and similar metres, on
    // every beat when a bar has many (10/8): never faster than four strokes
    // a second at normal speed.
    final beatsPerBar = (barTicks / beatTicks).round();
    final subdivide = beatsPerBar <= 4 && beatTicks / 2 / ticksPerSecond >= .25;
    final step = subdivide ? beatTicks / 2 : beatTicks;
    final stepsPerBar = (barTicks / step).round();
    final lastBar = math.max(
      0,
      ((last - firstBeat) / barTicks - 1e-6).floor(),
    );
    // Two guitars at once in every bar: one strums, the other picks the
    // chord note by note. The last bar rings out on one strummed chord.
    final strumGap = .016 * ticksPerSecond;
    // Played by hand: every stroke a touch behind the grid, never ahead of
    // it so nothing sounds before its chord, and a little louder or softer
    // than the one before. Seeded, so a song always sounds the same.
    final hand = math.Random(7);
    double late() => hand.nextDouble() * .008 * ticksPerSecond;
    double touch() => .88 + .24 * hand.nextDouble();

    for (var i = 0; ; i++) {
      final t = firstBeat + i * step;
      if (t >= last - 1e-6) break;
      final span = spanAt(t);
      if (span == null) continue;
      final chord = span.chord;
      final bar = i ~/ stepsPerBar, inBar = i % stepsPerBar;
      if (bar == lastBar) {
        if (inBar == 0) {
          final length = math.min(span.end, firstBeat + (bar + 1) * barTicks);
          _strum(
            events,
            chord,
            t,
            length - t,
            asked(t, length),
            down: true,
            gain: .11,
            gap: strumGap,
          );
        }
      } else {
        // The strumming guitar: down on the beats, up on the off-beats,
        // D, D U, U D U in 4/4, no stroke after the one and on the three.
        bool rests(int k) =>
            subdivide && (k == 1 || (stepsPerBar == 8 && k == 4));
        final down = inBar.isEven;
        if (!rests(inBar)) {
          var next = inBar + 1;
          while (next < stepsPerBar && rests(next)) {
            next++;
          }
          final length = math.min((next - inBar) * step, span.end - t);
          final at = t + late();
          _strum(
            events,
            chord,
            at,
            length - (at - t),
            asked(t, t + length),
            down: down,
            gain: (inBar == 0 ? .1 : (down ? .08 : .055)) * touch(),
            gap: strumGap,
          );
        }
        // The picking guitar: thumb on the lowest string, then the
        // fingers up and down, p i m a m i, over all five strings in a bar
        // of eight, letting each note ring under the next.
        final pattern = stepsPerBar == 8
            ? const [0, 1, 2, 3, 4, 3, 2, 1]
            : const [0, 1, 2, 3, 2, 1];
        final voicing = _guitarVoicing(chord);
        final midi = voicing[pattern[inBar % pattern.length] % voicing.length];
        final length = math.min(2 * step, span.end - t);
        final at = t + late();
        if (length - (at - t) > 1e-6 &&
            !asked(t, t + length).contains(midi % 12)) {
          events.add(
            SoundEvent(
              at,
              Voice.picked,
              _midiFrequency(midi),
              length - (at - t),
              (inBar == 0 ? .12 : .095) * touch(),
            ),
          );
        }
      }
      // The bass: the chord's bass note on the first beat, its fifth
      // halfway through the bar.
      if ((t - firstBeat) % halfBar < 1e-6) {
        final length = math.min(halfBar, span.end - t);
        final avoidBass = asked(t, t + length);
        final first = (t - firstBeat) % barTicks < 1e-6;
        // The fifth of the chord; diminished and augmented ones have
        // their own.
        final fifth =
            (chord.root +
                chord.intervals[math.min(2, chord.intervals.length - 1)]) %
            12;
        final pc = [
          if (first) chord.bassNote,
          fifth,
          if (!first) chord.bassNote,
          ...chord.tones,
        ].where((pc) => !avoidBass.contains(pc)).firstOrNull;
        if (pc != null) {
          // Between E2 and D#3, below the guitar's melody.
          final midi = 40 + (pc - 40) % 12;
          events.add(
            SoundEvent(t, Voice.bass, _midiFrequency(midi), length, .3),
          );
        }
      }
    }

    // Strings hold the chord underneath, each tone as long as the player
    // is not asked for it, bowed afresh at least every three seconds.
    final padTail = .5 * ticksPerSecond;
    final maxPad = math.max(step, (3 * ticksPerSecond / step).floor() * step);
    final open = <int, ({double start, double until})>{};
    void close(int midi) {
      final n = open.remove(midi)!;
      events.add(
        SoundEvent(
          n.start,
          Voice.strings,
          _midiFrequency(midi),
          n.until - n.start,
          .065,
        ),
      );
    }

    for (var i = 0; ; i++) {
      final t = firstBeat + i * step;
      if (t >= last - 1e-6) break;
      final span = spanAt(t);
      final until = span == null ? t : math.min(t + step, span.end);
      final avoid = span == null ? const <int>{} : asked(t, until + padTail);
      final voicing = {
        if (span != null)
          for (final pc in span.chord.tones)
            if (!avoid.contains(pc)) 55 + (pc - 55) % 12,
      };
      for (final midi in [...open.keys]) {
        final n = open[midi]!;
        if (!voicing.contains(midi) ||
            (n.until - t).abs() > 1e-6 ||
            until - n.start > maxPad + 1e-6) {
          close(midi);
        }
      }
      for (final midi in voicing) {
        final n = open[midi];
        open[midi] = (start: n?.start ?? t, until: until);
      }
    }
    for (final midi in [...open.keys]) {
      close(midi);
    }

    // Now and then a second voice under the melody, a third under that on
    // long notes: on notes of a beat or longer, from the chord's own tones,
    // in every bar but the last.
    for (final n in melody) {
      if (n.length < beatTicks - 1e-6) continue;
      final bar = ((n.start - firstBeat) / barTicks + 1e-6).floor();
      if (bar < 0 || bar == lastBar) continue;
      final span = spanAt(n.start);
      if (span == null) continue;
      final length = math.min(n.length, span.end - n.start);
      final avoid = asked(n.start, n.start + length);
      int? below(int midi) {
        for (final d in const [3, 4, 5]) {
          final m = midi - d;
          if (m >= 48 &&
              span.chord.tones.contains(m % 12) &&
              !avoid.contains(m % 12)) {
            return m;
          }
        }
        return null;
      }

      final melodyMidi =
          (12 * math.log(n.frequency / 440) / math.ln2 + 69).round();
      final second = below(melodyMidi);
      if (second == null) continue;
      final third = n.length >= 2 * beatTicks - 1e-6 ? below(second) : null;
      for (final m in [second, if (third != null) third]) {
        events.add(
          SoundEvent(n.start, Voice.harmony, _midiFrequency(m), length, .12),
        );
      }
    }

    for (final n in melody) {
      events.add(SoundEvent(n.start, Voice.guitar, n.frequency, n.length, .5));
    }
    events.sort((a, b) => a.tick.compareTo(b.tick));
    return Arrangement._(events, spans);
  }

  /// The chord as a guitar holds it, lowest string first: its root between
  /// C3 and B3, then its tones upwards, five strings up to G4.
  static List<int> _guitarVoicing(ChordSymbol chord) {
    final voicing = [48 + (chord.bassNote - 48) % 12];
    final order = [for (final i in chord.intervals) (chord.root + i) % 12];
    for (var k = 0; voicing.length < 5 && k < 24; k++) {
      final pc = order[k % order.length];
      if (pc == voicing.last % 12) continue;
      var midi = voicing.last + 1;
      while (midi % 12 != pc) {
        midi++;
      }
      if (midi > 67) break;
      voicing.add(midi);
    }
    return voicing;
  }

  /// One stroke of the strumming guitar: down from the lowest string to
  /// the highest, or up over the top three, a few milliseconds apart. A
  /// tone the player is asked for is left out; nothing foreign takes its
  /// place.
  static void _strum(
    List<SoundEvent> events,
    ChordSymbol chord,
    double t,
    double length,
    Set<int> avoid, {
    required bool down,
    required double gain,
    required double gap,
  }) {
    if (length <= 1e-6) return;
    final all = _guitarVoicing(chord);
    final strings = down
        ? all
        : all.sublist(math.max(0, all.length - 3)).reversed.toList();
    var k = 0;
    for (final midi in strings) {
      if (avoid.contains(midi % 12)) continue;
      final at = t + k++ * gap;
      events.add(
        SoundEvent(
          at,
          Voice.chord,
          _midiFrequency(midi),
          length - (at - t),
          gain,
        ),
      );
    }
  }

  /// Picks a chord for every bar: the triad of the song's key that
  /// holds most of the melody sounding in it, staying on the chord before
  /// when that fits as well.
  static List<ChordSymbol> _harmonize(
    List<MelodyNote> melody,
    double firstBeat,
    double bar,
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
    final count = math.max(1, ((end - firstBeat) / bar).ceil());
    final chords = <ChordSymbol>[];
    var previous = ChordSymbol.triad(key.tonic, minor: key.minor);
    for (var i = 0; i < count; i++) {
      final from = firstBeat + i * bar, to = from + bar;
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

  /// The key of the melody, by the Krumhansl-Schmuckler profiles, its last
  /// note weighted as the likely tonic.
  static ({int tonic, bool minor}) _key(List<MelodyNote> melody) {
    final best = keyRanking(melody).first;
    return (tonic: best.tonic, minor: best.minor);
  }

  /// All 24 major and minor keys, best match for the melody first, with
  /// their Krumhansl-Schmuckler score, the last note counted twice: how
  /// close the runner-up comes shows how sure the guess is.
  static List<({int tonic, bool minor, double score})> keyRanking(
    List<MelodyNote> melody,
  ) {
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
    // The last note counts twice: melodies, Arabic ones above all, come to
    // rest on their tonic. Without this a long fifth can outweigh it, as A
    // did in Ba’dak Ala Bali, which ends on D.
    if (melody.isNotEmpty) {
      final last = melody.reduce(
        (a, b) => b.start + b.length > a.start + a.length ? b : a,
      );
      weight[pitchClass(last.frequency)] += last.length;
    }
    final ranking = <({int tonic, bool minor, double score})>[];
    for (var tonic = 0; tonic < 12; tonic++) {
      for (final isMinor in [false, true]) {
        final profile = isMinor ? minor : major;
        var s = 0.0;
        for (var pc = 0; pc < 12; pc++) {
          s += weight[pc] * profile[(pc - tonic) % 12];
        }
        ranking.add((tonic: tonic, minor: isMinor, score: s));
      }
    }
    // Of equal scores the first tried wins, as it always has.
    int order(({int tonic, bool minor, double score}) k) =>
        k.tonic * 2 + (k.minor ? 1 : 0);
    ranking.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : order(a).compareTo(order(b));
    });
    return ranking;
  }
}

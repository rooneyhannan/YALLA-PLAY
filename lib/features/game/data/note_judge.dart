import 'dart:math' as math;

import '../../tuner/data/tuning.dart';
import 'song_data.dart';

/// Pitch of a tab note in standard tuning: the open string raised by one
/// semitone per fret.
double noteFrequency(Note note) =>
    standardTuning[note.s - 1].frequency * math.pow(2, note.f / 12);

/// Wider than the tuner's ±5 cents: while playing, the right semitone is
/// what counts.
const playCentsTolerance = 40.0;

/// Whether [heard] is the wanted note. A pitch detector can slip an octave
/// on a strong overtone, so the octave above or below also counts.
bool pitchMatches(double heard, double wanted) {
  final cents = centsBetween(heard, wanted);
  return [
    0,
    1200,
    -1200,
  ].any((octave) => (cents - octave).abs() <= playCentsTolerance);
}

enum Verdict { perfect, early, late, missed }

/// Tells a fresh pluck from a string that is still ringing, so a held note
/// does not also count for the next note of the same pitch.
class OnsetDetector {
  double _lastLevel = 0;
  double? _lastPitch;

  /// True when this frame starts a new note: the level jumps well above the
  /// frame before, or the pitch moves to another note.
  bool feed(double level, double? frequency) {
    final jumped = level > .004 && level > _lastLevel * 1.8;
    final moved =
        frequency != null &&
        _lastPitch != null &&
        centsBetween(frequency, _lastPitch!).abs() > 80;
    _lastLevel = level;
    if (frequency != null) _lastPitch = frequency;
    return jumped || moved;
  }
}

/// Judges the notes of a song against what the microphone hears.
///
/// Times are ticks of the song; windows are in seconds, so they stay fair
/// at every playback speed.
class NoteJudge {
  /// When each note is due, in ticks.
  final List<double> starts;
  final List<double> frequencies;
  final List<Verdict?> verdicts;

  static const perfectWindow = .1, earlyWindow = .2, lateWindow = .35;

  int score = 0, streak = 0, bestStreak = 0;

  /// For practice: the song waits at each note until it is played, so no
  /// note is ever missed and one played after its window counts as late.
  bool patient;

  NoteJudge({
    required this.starts,
    required this.frequencies,
    this.patient = false,
  }) : verdicts = List.filled(starts.length, null);

  /// The first note not judged yet, or null when all are.
  int? get firstOpen {
    final i = verdicts.indexOf(null);
    return i < 0 ? null : i;
  }

  /// ×1, rising by one every 8 notes in a row, up to ×4.
  int get multiplier => math.min(4, 1 + streak ~/ 8);

  int get judged => verdicts.where((v) => v != null).length;

  int get hits =>
      verdicts.where((v) => v != null && v != Verdict.missed).length;

  /// Share of judged notes that were hit, 0 to 1.
  double get accuracy => judged == 0 ? 0 : hits / judged;

  /// 3 stars from 90 %, 2 from 70 %, 1 from 40 %.
  int get stars => accuracy >= .9
      ? 3
      : accuracy >= .7
      ? 2
      : accuracy >= .4
      ? 1
      : 0;

  /// A pluck of [frequency] heard at [tick]. Returns the note it scored, or
  /// null when it matched none.
  int? pluck(double tick, double frequency, {required double ticksPerSecond}) =>
      pluckWhere(
        tick,
        (wanted) => pitchMatches(frequency, wanted),
        ticksPerSecond: ticksPerSecond,
      );

  /// Scores note [i] as played at [tick], when that is within its window
  /// (and, while practising, it is the next note). Returns whether it did.
  bool pluckNote(int i, double tick, {required double ticksPerSecond}) {
    if (verdicts[i] != null) return false;
    if (patient && i != firstOpen) return false;
    final offset = (tick - starts[i]) / ticksPerSecond;
    if (offset < -earlyWindow || (offset > lateWindow && !patient)) {
      return false;
    }
    _score(i, offset);
    return true;
  }

  void _score(int i, double offset) {
    final verdict = offset.abs() <= perfectWindow
        ? Verdict.perfect
        : offset < 0
        ? Verdict.early
        : Verdict.late;
    verdicts[i] = verdict;
    // The multiplier earned so far pays for this note.
    score += (verdict == Verdict.perfect ? 100 : 50) * multiplier;
    streak++;
    bestStreak = math.max(bestStreak, streak);
  }

  /// A pluck at [tick] that [sounds] like some of the due notes: scores the
  /// first one whose frequency it accepts.
  int? pluckWhere(
    double tick,
    bool Function(double frequency) sounds, {
    required double ticksPerSecond,
  }) {
    for (var i = 0; i < starts.length; i++) {
      if (verdicts[i] != null) continue;
      final offset = (tick - starts[i]) / ticksPerSecond;
      if (offset > lateWindow && !patient) continue;
      if (offset < -earlyWindow) break;
      if (!sounds(frequencies[i])) {
        // While practising, the notes are played strictly in order.
        if (patient) break;
        continue;
      }
      _score(i, offset);
      return i;
    }
    return null;
  }

  /// Marks notes whose window has passed without a pluck as missed and
  /// returns them.
  List<int> expire(double tick, {required double ticksPerSecond}) {
    final missed = <int>[];
    if (patient) return missed;
    for (var i = 0; i < starts.length; i++) {
      if (verdicts[i] != null) continue;
      if ((tick - starts[i]) / ticksPerSecond <= lateWindow) break;
      verdicts[i] = Verdict.missed;
      streak = 0;
      missed.add(i);
    }
    return missed;
  }

  void reset() {
    verdicts.fillRange(0, verdicts.length, null);
    score = streak = bestStreak = 0;
  }
}

/// Listens for each expected note itself: its pitch class clearly above the
/// neighbouring semitones and just grown louder. Works while the backing
/// plays, which never sounds that pitch class, and while other strings ring.
class ExpectedNoteDetector {
  /// Tuned on recordings with the backing louder than the guitar.
  static const minContrast = 3.0, minLevel = .3, minRise = 2.0;

  /// The note's strength in the last few frames.
  final _history = <int, List<double>>{};

  /// Whether note [i] at [frequency] has just started in [frame], whose
  /// RMS level is [rms].
  bool heard(
    int i,
    List<double> frame,
    num sampleRate,
    double frequency,
    double rms,
  ) {
    final strength = noteStrength(frame, sampleRate, frequency);
    final history = _history.putIfAbsent(i, () => []);
    final before = history.isEmpty ? 0.0 : history.reduce(math.min);
    history.add(strength.level);
    if (history.length > 3) history.removeAt(0);
    return strength.contrast >= minContrast &&
        strength.level >= minLevel * rms &&
        strength.level >= minRise * before;
  }

  void reset() => _history.clear();
}

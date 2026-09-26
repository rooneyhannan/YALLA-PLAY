import 'dart:math' as math;
import 'dart:typed_data';

/// One open string in standard tuning. Index 0 is the thin high E string,
/// matching the order of the pegs and the game board.
class GuitarString {
  final String label;
  final String note;
  final double frequency;
  const GuitarString(this.label, this.note, this.frequency);
}

const standardTuning = <GuitarString>[
  GuitarString('E', 'E4', 329.63),
  GuitarString('H', 'B3', 246.94),
  GuitarString('G', 'G3', 196.00),
  GuitarString('D', 'D3', 146.83),
  GuitarString('A', 'A2', 110.00),
  GuitarString('E', 'E2', 82.41),
];

/// Cents within which a string counts as tuned.
const inTuneCents = 5.0;

double centsBetween(double frequency, double target) =>
    1200 * math.log(frequency / target) / math.ln2;

class TuningReading {
  /// The heard pitch, moved into the octave of the compared string.
  final double frequency;
  final int stringIndex;
  final double cents;
  const TuningReading(this.frequency, this.stringIndex, this.cents);
  bool get inTune => cents.abs() <= inTuneCents;
}

/// Cents from [target] to the same note name as [frequency] in any octave,
/// from -600 to 600. Guitar strings often sound a strong overtone, so a
/// pitch detector can read an octave off; the note name stays right.
double _noteCents(double frequency, double target) {
  final cents = centsBetween(frequency, target);
  return cents - 1200 * (cents / 1200).roundToDouble();
}

/// Compares [frequency] with [target], or with the closest string when
/// [target] is null (automatic mode).
TuningReading readTuning(double frequency, {int? target}) {
  var index = target ?? 0;
  if (target == null) {
    for (var i = 1; i < standardTuning.length; i++) {
      final candidate = _noteCents(frequency, standardTuning[i].frequency);
      final best = _noteCents(frequency, standardTuning[index].frequency);
      // Both E strings share a note name; then the nearer octave decides.
      final sameNote = (candidate.abs() - best.abs()).abs() < 1;
      if (sameNote
          ? centsBetween(frequency, standardTuning[i].frequency).abs() <
                centsBetween(frequency, standardTuning[index].frequency).abs()
          : candidate.abs() < best.abs()) {
        index = i;
      }
    }
  }
  final string = standardTuning[index].frequency;
  final cents = _noteCents(frequency, string);
  return TuningReading(string * math.pow(2, cents / 1200), index, cents);
}

/// Median of the most recent pitches, so single misdetections do not make
/// the needle jump.
class PitchSmoother {
  final int size;
  final _recent = <double>[];
  PitchSmoother({this.size = 5});

  double add(double frequency) {
    if (_recent.isNotEmpty &&
        centsBetween(frequency, _recent.last).abs() > 100) {
      // A new string was plucked: start over instead of averaging two notes.
      _recent.clear();
    }
    _recent.add(frequency);
    if (_recent.length > size) _recent.removeAt(0);
    final sorted = [..._recent]..sort();
    return sorted[sorted.length ~/ 2];
  }

  void reset() => _recent.clear();
}

/// Lets through only frames loud enough to trust. Besides a fixed floor,
/// a fading string is dropped once it falls far below its pluck, where
/// noise and other strings ringing along bend the reading.
class LevelGate {
  final double floor, ratio, decay;
  double _peak = 0;
  LevelGate({this.floor = .0025, this.ratio = .08, this.decay = .98});

  bool open(double rms) {
    _peak = math.max(rms, _peak * decay);
    return rms >= floor && rms >= _peak * ratio;
  }
}

/// YIN pitch detection (de Cheveigné & Kawahara, 2002).
double? detectPitch(
  List<double> buffer,
  num sampleRate, {
  double minHz = 60,
  double maxHz = 1000,
}) {
  final window = buffer.length ~/ 2;
  final minLag = math.max(2, sampleRate ~/ maxHz);
  final maxLag = math.min(window - 2, sampleRate ~/ minHz);
  if (maxLag <= minLag) return null;

  // Cumulative mean normalized difference, only up to the longest period
  // of interest to keep each poll cheap.
  final cmndf = Float64List(maxLag + 2)..[0] = 1;
  var runningSum = 0.0;
  for (var tau = 1; tau <= maxLag + 1; tau++) {
    var diff = 0.0;
    for (var i = 0; i < window; i++) {
      final d = buffer[i] - buffer[i + tau];
      diff += d * d;
    }
    runningSum += diff;
    cmndf[tau] = runningSum > 0 ? diff * tau / runningSum : 1;
  }

  // First dip below the threshold, walked down to its local minimum.
  const threshold = 0.1;
  var tau = -1;
  for (var t = minLag; t <= maxLag; t++) {
    if (cmndf[t] < threshold) {
      while (t < maxLag && cmndf[t + 1] < cmndf[t]) {
        t++;
      }
      tau = t;
      break;
    }
  }
  if (tau < 0) return null;

  // Guitar strings often have a stronger second or third harmonic than
  // fundamental, so the first dip can sit at a half or a third of the real
  // period. The real period repeats almost perfectly; prefer it when it is
  // clearly more periodic than the dip found first.
  for (final multiple in const [3, 2]) {
    final longer = _localMinimumNear(cmndf, tau * multiple, maxLag);
    if (longer != null &&
        cmndf[tau] - cmndf[longer] > .03 &&
        cmndf[longer] < cmndf[tau] * .35) {
      tau = longer;
      break;
    }
  }

  // Parabolic interpolation for sub-sample accuracy.
  final s0 = cmndf[tau - 1], s1 = cmndf[tau], s2 = cmndf[tau + 1];
  final denom = 2 * (s0 - 2 * s1 + s2);
  final shift = denom.abs() > 1e-12 ? (s0 - s2) / denom : 0.0;
  final hz = sampleRate / (tau + shift);
  return hz >= minHz && hz <= maxHz ? hz : null;
}

/// The lowest point within 3% of [lag], or null when out of range.
int? _localMinimumNear(Float64List cmndf, int lag, int maxLag) {
  final from = (lag * .97).floor(), to = (lag * 1.03).ceil();
  if (to > maxLag) return null;
  var best = from;
  for (var t = from + 1; t <= to; t++) {
    if (cmndf[t] < cmndf[best]) best = t;
  }
  return best;
}

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
  final double frequency;
  final int stringIndex;
  final double cents;
  const TuningReading(this.frequency, this.stringIndex, this.cents);
  bool get inTune => cents.abs() <= inTuneCents;
}

/// Compares [frequency] with [target], or with the closest string when
/// [target] is null (automatic mode).
TuningReading readTuning(double frequency, {int? target}) {
  var index = target ?? 0;
  if (target == null) {
    for (var i = 1; i < standardTuning.length; i++) {
      if (centsBetween(frequency, standardTuning[i].frequency).abs() <
          centsBetween(frequency, standardTuning[index].frequency).abs()) {
        index = i;
      }
    }
  }
  var cents = centsBetween(frequency, standardTuning[index].frequency);
  // A detector that locks onto the first overtone reads a whole octave off.
  // Near a whole octave, compare with the octave instead.
  if (target != null && (cents.abs() - 1200).abs() < 300) {
    cents -= 1200 * cents.sign;
  }
  return TuningReading(frequency, index, cents);
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
  const threshold = 0.15;
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

  // Parabolic interpolation for sub-sample accuracy.
  final s0 = cmndf[tau - 1], s1 = cmndf[tau], s2 = cmndf[tau + 1];
  final denom = 2 * (s0 - 2 * s1 + s2);
  final shift = denom.abs() > 1e-12 ? (s0 - s2) / denom : 0.0;
  final hz = sampleRate / (tau + shift);
  return hz >= minHz && hz <= maxHz ? hz : null;
}

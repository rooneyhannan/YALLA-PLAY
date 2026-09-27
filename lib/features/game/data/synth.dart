import 'dart:math' as math;
import 'dart:typed_data';

/// The sounds the play screen makes.
enum Voice {
  /// Metronome tick, and the stronger one on the first beat of a bar.
  click,
  accent,

  /// The melody, as a plucked string.
  guitar,

  /// Backing: soft keys for the chords and a round bass.
  chord,
  bass,
}

/// Samples of one sound of [voice] at [frequency], from its attack until it
/// has died away. Built in code, so the app needs no sound files and every
/// pitch sounds the same on every platform.
Float32List synthesize(Voice voice, double frequency, int sampleRate) =>
    switch (voice) {
      Voice.click => _click(1000, .5, sampleRate),
      Voice.accent => _click(1600, .8, sampleRate),
      Voice.guitar => _pluck(frequency, sampleRate),
      Voice.chord => _tone(frequency, sampleRate, const [1, .35, .12], 1.1),
      Voice.bass => _tone(frequency, sampleRate, const [1, .5, .2], .9),
    };

/// A classic metronome click: a short, bright sine burst.
Float32List _click(double hz, double level, int rate) {
  final out = Float32List((rate * .03).round());
  for (var i = 0; i < out.length; i++) {
    final t = i / rate;
    out[i] = level * math.sin(2 * math.pi * hz * t) * math.exp(-t / .004);
  }
  return out;
}

/// Karplus-Strong plucked string: a burst of noise circulating in a delay
/// line of one period, softened a little on every pass.
Float32List _pluck(double hz, int rate) {
  final out = Float32List((rate * 2.5).round());
  final period = math.max(2, (rate / hz).round());
  final random = math.Random(hz.round());
  final line = List<double>.generate(
    period,
    (_) => random.nextDouble() * 2 - 1,
  );
  // A gentler attack than raw noise, closer to a finger than a pick.
  for (var i = 1; i < period; i++) {
    line[i] = .6 * line[i] + .4 * line[i - 1];
  }
  for (var i = 0; i < out.length; i++) {
    final j = i % period;
    out[i] = line[j];
    line[j] = .997 * .5 * (line[j] + line[(j + 1) % period]);
  }
  return _normalized(out, .7);
}

/// A tone of a few harmonics with a quick attack and a long fade; higher
/// harmonics fade faster, as on a piano.
Float32List _tone(
  double hz,
  int rate,
  List<double> harmonics,
  double decaySeconds,
) {
  final out = Float32List((rate * 2.5).round());
  for (var i = 0; i < out.length; i++) {
    final t = i / rate;
    final attack = math.min(1.0, t / .008);
    var v = 0.0;
    for (var h = 0; h < harmonics.length; h++) {
      v +=
          harmonics[h] *
          math.sin(2 * math.pi * hz * (h + 1) * t) *
          math.exp(-t * (h + 1) / decaySeconds);
    }
    out[i] = attack * v;
  }
  return _normalized(out, .7);
}

Float32List _normalized(Float32List samples, double peak) {
  var max = 0.0;
  for (final v in samples) {
    max = math.max(max, v.abs());
  }
  if (max > 0) {
    for (var i = 0; i < samples.length; i++) {
      samples[i] *= peak / max;
    }
  }
  return samples;
}

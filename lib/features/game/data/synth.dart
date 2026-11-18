import 'dart:math' as math;
import 'dart:typed_data';

/// The sounds the play screen makes.
enum Voice {
  /// Metronome tick, and the stronger one on the first beat of a bar.
  click,
  accent,

  /// The melody, as a plucked string.
  guitar,

  /// Backing: a second guitar strumming or picking the chords, a round
  /// bass, strings holding the chords underneath, and now and then a
  /// second and third voice under the melody.
  chord,
  bass,
  strings,
  harmony,
}

/// How long a sound of [voice] takes to fade once it is let go, in
/// seconds: the time constant of its release.
double releaseSeconds(Voice voice) => switch (voice) {
  Voice.strings => .15,
  Voice.bass => .06,
  _ => .03,
};

/// Samples of one sound of [voice] at [frequency], from its attack until it
/// has died away. Built in code, so the app needs no sound files and every
/// pitch sounds the same on every platform.
Float32List synthesize(Voice voice, double frequency, int sampleRate) =>
    switch (voice) {
      Voice.click => _click(1000, .5, sampleRate),
      Voice.accent => _click(1600, .8, sampleRate),
      Voice.guitar => _pluck(frequency, sampleRate),
      Voice.chord => _pluck(frequency, sampleRate, soften: .5, decay: .995),
      Voice.harmony => _pluck(frequency, sampleRate, soften: .55, decay: .996),
      Voice.bass => _tone(frequency, sampleRate, const [1, .5, .2], .9),
      Voice.strings => _strings(frequency, sampleRate),
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
/// line of one period, softened a little on every pass. A higher [soften]
/// gives a rounder attack, a lower [decay] a shorter ring.
Float32List _pluck(
  double hz,
  int rate, {
  double soften = .4,
  double decay = .997,
}) {
  final out = Float32List((rate * 2.5).round());
  final period = math.max(2, (rate / hz).round());
  final random = math.Random(hz.round());
  final line = List<double>.generate(
    period,
    (_) => random.nextDouble() * 2 - 1,
  );
  // A gentler attack than raw noise, closer to a finger than a pick.
  for (var i = 1; i < period; i++) {
    line[i] = (1 - soften) * line[i] + soften * line[i - 1];
  }
  for (var i = 0; i < out.length; i++) {
    final j = i % period;
    out[i] = line[j];
    line[j] = decay * .5 * (line[j] + line[(j + 1) % period]);
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

/// A string section holding a note: three slightly detuned, softly
/// filtered saw waves with a gentle vibrato, swelling in like a bow. Long
/// enough for the longest held chord even at half speed; the sound engine
/// fades it out when the chord ends.
Float32List _strings(double hz, int rate) {
  // One period of a saw wave, its harmonics up to about 5 kHz rolled off.
  const size = 2048;
  final table = Float64List(size);
  final harmonics = math.max(1, math.min(10, (5000 / hz).floor()));
  for (var h = 1; h <= harmonics; h++) {
    final amp = 1 / (h * h * .6 + h * .4);
    for (var i = 0; i < size; i++) {
      table[i] += amp * math.sin(2 * math.pi * h * i / size);
    }
  }
  final out = Float32List(rate * 8);
  const detune = [-.004, 0, .0045];
  final phase = List.filled(detune.length, 0.0);
  for (var i = 0; i < out.length; i++) {
    final t = i / rate;
    final vibrato = 1 + .0025 * math.sin(2 * math.pi * 5.2 * t);
    var v = 0.0;
    for (var k = 0; k < detune.length; k++) {
      v += table[(phase[k] * size).floor() % size];
      phase[k] = (phase[k] + hz * (1 + detune[k]) * vibrato / rate) % 1;
    }
    out[i] = math.min(1.0, t / .25) * v;
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

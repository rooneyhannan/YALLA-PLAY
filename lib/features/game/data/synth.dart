import 'dart:math' as math;
import 'dart:typed_data';

/// The sounds the play screen makes.
enum Voice {
  /// Metronome tick, and the stronger one on the first beat of a bar.
  click,
  accent,

  /// The melody, as a plucked string.
  guitar,

  /// Backing: a second guitar strumming the chords, a third picking them
  /// at the same time, a plucked bass, strings holding the chords
  /// underneath, and now and then a second and third voice under the
  /// melody.
  chord,
  picked,
  bass,
  strings,
  harmony,
}

/// How long a sound of [voice] takes to fade once it is let go, in
/// seconds: the time constant of its release.
double releaseSeconds(Voice voice) => switch (voice) {
  Voice.strings => .2,
  Voice.harmony => .12,
  Voice.bass => .08,
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
      // Long enough to ring out the last chord, even at half speed.
      Voice.chord => _pluck(
        frequency,
        sampleRate,
        soften: .45,
        decay: .996,
        seconds: 6,
        pickAt: .18,
      ),
      // Fingers rather than a pick: rounder, plucked near the soundhole.
      Voice.picked => _pluck(
        frequency,
        sampleRate,
        soften: .6,
        decay: .997,
        seconds: 4,
        pickAt: .3,
      ),
      // Bowed softly, like a few violas behind the singer.
      Voice.harmony => _strings(
        frequency,
        sampleRate,
        brightness: 2500,
        attack: .12,
      ),
      Voice.bass => _bass(frequency, sampleRate),
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
/// gives a rounder attack, a lower [decay] a shorter ring. With [pickAt],
/// the string is plucked at that fraction of its length: the overtones
/// with a node there are missing, as on a real string, which sounds less
/// like noise and more like wood and nylon.
Float32List _pluck(
  double hz,
  int rate, {
  double soften = .4,
  double decay = .997,
  double seconds = 2.5,
  double? pickAt,
}) {
  final out = Float32List((rate * seconds).round());
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
  if (pickAt != null) {
    final offset = math.max(1, (pickAt * period).round());
    final plucked = [
      for (var i = 0; i < period; i++)
        line[i] - line[(i - offset) % period],
    ];
    line.setAll(0, plucked);
  }
  for (var i = 0; i < out.length; i++) {
    final j = i % period;
    out[i] = line[j];
    line[j] = decay * .5 * (line[j] + line[(j + 1) % period]);
  }
  return _normalized(out, .7);
}

/// A plucked bass string: a dark Karplus-Strong pluck with a round sine
/// underneath for the weight of the body, fading over about a second.
Float32List _bass(double hz, int rate) {
  final string = _pluck(
    hz,
    rate,
    soften: .8,
    decay: .995,
    seconds: 2.5,
    pickAt: .2,
  );
  for (var i = 0; i < string.length; i++) {
    final t = i / rate;
    final body =
        math.min(1.0, t / .005) *
        math.sin(2 * math.pi * hz * t) *
        math.exp(-t / .9);
    string[i] = .55 * string[i] + .45 * body;
  }
  return _normalized(string, .7);
}

/// A string section holding a note: five players, each slightly out of
/// tune with the others and with a vibrato of their own, bowing softly
/// filtered saw waves that swell in like a bow. Long enough for the
/// longest held chord even at half speed; the sound engine fades it out
/// when the chord ends. A lower [brightness], in hertz, darkens it.
Float32List _strings(
  double hz,
  int rate, {
  double brightness = 4000,
  double attack = .3,
  double seconds = 8,
}) {
  // One period of a saw wave, its harmonics above [brightness] left out
  // and the high ones rolled off.
  const size = 2048;
  final table = Float64List(size);
  final harmonics = math.max(1, math.min(12, (brightness / hz).floor()));
  for (var h = 1; h <= harmonics; h++) {
    final amp = 1 / (h * h * .6 + h * .4);
    for (var i = 0; i < size; i++) {
      table[i] += amp * math.sin(2 * math.pi * h * i / size);
    }
  }
  final out = Float32List((rate * seconds).round());
  const detune = [-.006, -.0025, 0, .003, .0065];
  const vibratoHz = [4.9, 5.4, 5.1, 5.7, 5.25];
  const vibratoPhase = [0.0, 1.3, 2.9, .7, 4.1];
  final phase = [for (var k = 0; k < detune.length; k++) k / detune.length];
  // A gentle low-pass, the body of the instruments.
  final smooth = math.exp(-2 * math.pi * brightness / rate);
  var last = 0.0;
  // Each player's step through the table, renewed every few samples:
  // vibrato changes far too slowly to need more, and it saves most of the
  // work.
  final advance = List.filled(detune.length, 0.0);
  for (var i = 0; i < out.length; i++) {
    final t = i / rate;
    if (i % 32 == 0) {
      // Vibrato sets in after the bow has settled, as players do.
      final depth = .003 * math.min(1.0, t / .6);
      for (var k = 0; k < detune.length; k++) {
        final wobble = math.sin(
          2 * math.pi * vibratoHz[k] * t + vibratoPhase[k],
        );
        advance[k] = hz * (1 + detune[k]) * (1 + depth * wobble) / rate;
      }
    }
    var v = 0.0;
    for (var k = 0; k < detune.length; k++) {
      v += table[(phase[k] * size).floor() % size];
      phase[k] = (phase[k] + advance[k]) % 1;
    }
    last = (1 - smooth) * v + smooth * last;
    final swell = math.min(1.0, t / attack);
    out[i] = swell * swell * (3 - 2 * swell) * last;
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

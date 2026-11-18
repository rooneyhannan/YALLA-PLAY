import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'sound_engine.dart';
import 'synth.dart';

SoundEngine createPlatformSoundEngine() => WebSoundEngine();

/// Web Audio: every sound is synthesized once per pitch into a buffer and
/// then scheduled on the audio clock, so beats stay exact however the
/// frames run.
class WebSoundEngine implements SoundEngine {
  web.AudioContext? _ctx;
  web.GainNode? _out;

  /// Where the guitars, bass and strings also go to sound in a room.
  web.GainNode? _room;

  /// The metronome, past the compressor, so its clicks never duck the
  /// music.
  web.GainNode? _clicks;
  final _buffers = <String, web.AudioBuffer>{};
  final _sources = <web.AudioBufferSourceNode>{};

  @override
  Future<void> start() async {
    if (_ctx != null) return;
    try {
      // Created before the first await so it still counts as started by the tap.
      final ctx = _ctx = web.AudioContext();
      // A gentle compressor glues the instruments together and keeps
      // metronome, guitars, bass, strings and melody under full scale.
      final glue = ctx.createDynamicsCompressor()..connect(ctx.destination);
      glue.threshold.value = -14;
      glue.ratio.value = 2.5;
      glue.attack.value = .01;
      glue.release.value = .25;
      _out = ctx.createGain()
        ..gain.value = .8
        ..connect(glue);
      _clicks = ctx.createGain()
        ..gain.value = .8
        ..connect(ctx.destination);
      // A small warm room: a backing without one sounds dead, as if
      // played into a pillow.
      final reverb = ctx.createConvolver()..buffer = _roomResponse(ctx);
      reverb.connect(_out!);
      _room = ctx.createGain()
        ..gain.value = .35
        ..connect(reverb);
      await ctx.resume().toDart;
    } catch (_) {
      dispose();
    }
  }

  @override
  double? get time => _ctx?.currentTime;

  /// The echo of a small room, in stereo: noise dying away over about
  /// 1.8 seconds, its highs fading faster than its lows, as walls and air
  /// swallow them. Seeded, so the room is the same every time.
  static web.AudioBuffer _roomResponse(web.AudioContext ctx) {
    final rate = ctx.sampleRate;
    final length = (rate * 1.8).round();
    final buffer = ctx.createBuffer(2, length, rate);
    for (var channel = 0; channel < 2; channel++) {
      final random = math.Random(31 + channel);
      final samples = Float32List(length);
      var low = 0.0;
      for (var i = 0; i < length; i++) {
        final t = i / rate;
        // Darker as it dies away.
        final smooth = math.min(.97, .35 + t * .9);
        low = (1 - smooth) * (random.nextDouble() * 2 - 1) + smooth * low;
        // A few milliseconds of silence before the first reflections.
        final onset = math.min(1.0, math.max(0.0, (t - .008) / .01));
        samples[i] = onset * low * math.exp(-t / .38);
      }
      buffer.copyToChannel(samples.toJS, channel);
    }
    return buffer;
  }

  web.AudioBuffer _buffer(
    web.AudioContext ctx,
    Voice voice,
    double frequency,
  ) => _buffers.putIfAbsent('${voice.name}:${frequency.toStringAsFixed(1)}', () {
    final samples = synthesize(voice, frequency, ctx.sampleRate.round());
    return ctx.createBuffer(1, samples.length, ctx.sampleRate)
      ..copyToChannel(samples.toJS, 0);
  });

  @override
  void prepare(Voice voice, double frequency) {
    final ctx = _ctx;
    if (ctx != null) _buffer(ctx, voice, frequency);
  }

  @override
  void play(
    Voice voice,
    double frequency, {
    required double at,
    required double length,
    required double gain,
  }) {
    final ctx = _ctx, out = _out;
    if (ctx == null || out == null) return;
    final buffer = _buffer(ctx, voice, frequency);
    final release = releaseSeconds(voice);
    final level = ctx.createGain();
    level.gain
      ..setValueAtTime(gain, at)
      // Released like a lifted finger or bow rather than cut.
      ..setTargetAtTime(0, at + length, release);
    final source = ctx.createBufferSource()..buffer = buffer;
    source
      ..connect(level)
      ..start(at)
      ..stop(at + length + math.max(.25, 8 * release));
    final metronome = voice == Voice.click || voice == Voice.accent;
    final clicks = _clicks, room = _room;
    if (metronome && clicks != null) {
      level.connect(clicks);
    } else {
      level.connect(out);
      if (room != null) level.connect(room);
    }
    _sources.add(source);
    source.onended = ((web.Event _) {
      _sources.remove(source);
      level.disconnect();
    }).toJS;
  }

  @override
  void silence() {
    for (final source in _sources) {
      try {
        source.stop();
      } catch (_) {}
    }
    _sources.clear();
  }

  @override
  void dispose() {
    silence();
    _buffers.clear();
    final ctx = _ctx;
    _ctx = null;
    _out = null;
    _room = null;
    _clicks = null;
    if (ctx != null && ctx.state != 'closed') ctx.close();
  }
}

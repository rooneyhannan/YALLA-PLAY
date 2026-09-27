import 'dart:js_interop';

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
  final _buffers = <String, web.AudioBuffer>{};
  final _sources = <web.AudioBufferSourceNode>{};

  @override
  Future<void> start() async {
    if (_ctx != null) return;
    try {
      // Created before the first await so it still counts as started by the tap.
      final ctx = _ctx = web.AudioContext();
      // Headroom: metronome, chords, bass and melody together stay under
      // full scale.
      _out = ctx.createGain()
        ..gain.value = .8
        ..connect(ctx.destination);
      await ctx.resume().toDart;
    } catch (_) {
      dispose();
    }
  }

  @override
  double? get time => _ctx?.currentTime;

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
    final buffer = _buffers.putIfAbsent(
      '${voice.name}:${frequency.toStringAsFixed(1)}',
      () {
        final samples = synthesize(voice, frequency, ctx.sampleRate.round());
        return ctx.createBuffer(1, samples.length, ctx.sampleRate)
          ..copyToChannel(samples.toJS, 0);
      },
    );
    final level = ctx.createGain();
    level.gain
      ..setValueAtTime(gain, at)
      // Released like a lifted finger rather than cut.
      ..setTargetAtTime(0, at + length, .03);
    final source = ctx.createBufferSource()..buffer = buffer;
    source
      ..connect(level)
      ..start(at)
      ..stop(at + length + .25);
    level.connect(out);
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
    if (ctx != null && ctx.state != 'closed') ctx.close();
  }
}

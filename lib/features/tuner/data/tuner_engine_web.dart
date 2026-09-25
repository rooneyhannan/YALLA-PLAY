import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

import 'tuner_engine.dart';
import 'tuning.dart';

TunerEngine createPlatformTunerEngine() => WebTunerEngine();

/// getUserMedia → AnalyserNode, polled by a timer. Each poll runs YIN pitch
/// detection on the latest waveform.
class WebTunerEngine implements TunerEngine {
  web.AudioContext? _ctx;
  web.MediaStream? _stream;
  web.AnalyserNode? _analyser;
  Timer? _timer;

  static const _pollInterval = Duration(milliseconds: 50);
  static const _fftSize = 4096;
  static const _silenceRms = 0.006;

  @override
  Future<void> start(PitchCallback onPitch) async {
    stop();
    if (!web.window.navigator.has('mediaDevices')) {
      // Missing outside secure (https) pages and in some in-app browsers.
      throw const TunerException(TunerError.unsupported);
    }
    // Created before the first await so it still counts as started by the tap.
    final ctx = _ctx = web.AudioContext();
    final resumed = ctx.resume().toDart;
    try {
      _stream = await web.window.navigator.mediaDevices
          .getUserMedia(
            web.MediaStreamConstraints(
              // Voice processing filters out steady tones, which is exactly
              // what a plucked string is.
              audio: web.MediaTrackConstraints(
                echoCancellation: false.toJS,
                noiseSuppression: false.toJS,
                autoGainControl: false.toJS,
              ),
            ),
          )
          .toDart;
      await resumed;
    } catch (e) {
      stop();
      throw TunerException(_classify(e), '$e');
    }
    if (_ctx != ctx) return; // stopped while waiting for permission

    final analyser = _analyser = ctx.createAnalyser()..fftSize = _fftSize;
    ctx.createMediaStreamSource(_stream!).connect(analyser);
    final sampleRate = ctx.sampleRate;
    final samples = JSFloat32Array.withLength(_fftSize);

    _timer = Timer.periodic(_pollInterval, (_) {
      analyser.getFloatTimeDomainData(samples);
      final buffer = samples.toDart;
      var sumSq = 0.0;
      for (final v in buffer) {
        sumSq += v * v;
      }
      final rms = math.sqrt(sumSq / buffer.length);
      if (rms < _silenceRms) {
        onPitch(null, rms);
        return;
      }
      onPitch(detectPitch(buffer, sampleRate), rms);
    });
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
    _analyser?.disconnect();
    _analyser = null;
    _stream?.getTracks().toDart.forEach((track) => track.stop());
    _stream = null;
    if (_ctx != null && _ctx!.state != 'closed') _ctx!.close();
    _ctx = null;
  }
}

/// getUserMedia rejects with a DOMException whose name gives the reason.
TunerError _classify(Object error) {
  final name = switch (error) {
    JSObject js when js.has('name') => '${js['name'].dartify()}',
    _ => '$error',
  };
  return switch (name) {
    'NotAllowedError' || 'SecurityError' => TunerError.permissionDenied,
    'NotFoundError' ||
    'NotReadableError' ||
    'OverconstrainedError' => TunerError.noMicrophone,
    _ => TunerError.failed,
  };
}

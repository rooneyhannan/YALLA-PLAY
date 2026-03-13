import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:web_audio' as wa;

/// Minimal web tuner engine.
///
/// Architecture: getUserMedia → AudioContext → AnalyserNode
/// A dart Timer polls the AnalyserNode every [_pollInterval] ms and runs
/// YIN pitch detection on the time-domain buffer.  No streams, no
/// ScriptProcessorNode, no external packages.
class TunerEngine {
  wa.AudioContext? _ctx;
  wa.AnalyserNode? _analyser;
  html.MediaStream? _stream;
  Timer? _timer;

  bool _running = false;
  bool get running => _running;

  static const _pollInterval = Duration(milliseconds: 60);
  static const _fftSize = 4096;

  /// Start capturing + analysing.  MUST be called from a user gesture.
  Future<void> start(void Function(TunerResult result) onResult) async {
    if (_running) return;

    print('[TunerEngine] start()');

    // 1. Mic access
    final md = html.window.navigator.mediaDevices;
    if (md == null) {
      print('[TunerEngine] ERROR: mediaDevices is null (need HTTPS)');
      return;
    }
    _stream = await md.getUserMedia({'audio': true});
    print('[TunerEngine] getUserMedia OK — '
        '${_stream!.getAudioTracks().length} track(s)');

    // 2. Audio graph: mic → source → analyser → gain(0) → dest
    _ctx = wa.AudioContext();
    print('[TunerEngine] AudioContext sampleRate=${_ctx!.sampleRate}, '
        'state=${_ctx!.state}');

    if (_ctx!.state != 'running') {
      await _ctx!.resume();
      print('[TunerEngine] resume() → state=${_ctx!.state}');
    }

    final source = _ctx!.createMediaStreamSource(_stream!);
    _analyser = _ctx!.createAnalyser();
    _analyser!.fftSize = _fftSize;

    final gain = _ctx!.createGain();
    gain.gain!.value = 0; // mute playback

    source.connectNode(_analyser!);
    _analyser!.connectNode(gain);
    gain.connectNode(_ctx!.destination!);
    print('[TunerEngine] graph: source → analyser → gain(0) → dest');

    // 3. Poll with a timer
    final sampleRate = _ctx!.sampleRate!.toInt();
    final buf = Uint8List(_analyser!.frequencyBinCount!);
    _running = true;
    int tick = 0;

    _timer = Timer.periodic(_pollInterval, (_) {
      if (!_running || _analyser == null) return;
      tick++;

      try {
        _analyser!.getByteTimeDomainData(buf);

        // Convert 0..255 → -1..1  and compute RMS
        final n = buf.length;
        final floats = Float64List(n);
        double sumSq = 0;
        for (int i = 0; i < n; i++) {
          final v = (buf[i] - 128) / 128.0;
          floats[i] = v;
          sumSq += v * v;
        }
        final rms = math.sqrt(sumSq / n);

        if (tick <= 3 || tick % 50 == 0) {
          print('[TunerEngine] tick #$tick  rms=${rms.toStringAsFixed(4)}');
        }

        if (rms < 0.01) {
          onResult(TunerResult(frequency: null, rms: rms, note: '--'));
          return;
        }

        // YIN pitch detection
        final hz = _yin(floats, sampleRate);

        String note = '--';
        if (hz != null && hz > 20 && hz < 2000) {
          note = _hzToNote(hz);
        }

        if (hz != null && (tick <= 5 || tick % 30 == 0)) {
          print('[TunerEngine] pitch=${hz.toStringAsFixed(1)} Hz  note=$note');
        }

        onResult(TunerResult(
          frequency: (hz != null && hz > 20 && hz < 2000) ? hz : null,
          rms: rms,
          note: note,
        ));
      } catch (e) {
        print('[TunerEngine] poll error: $e');
      }
    });

    print('[TunerEngine] polling started');
  }

  void stop() {
    print('[TunerEngine] stop()');
    _running = false;
    _timer?.cancel();
    _timer = null;
    _analyser?.disconnect();
    _analyser = null;
    _stream?.getTracks().forEach((t) => t.stop());
    _stream = null;
    if (_ctx != null && _ctx!.state != 'closed') {
      _ctx!.close();
    }
    _ctx = null;
  }

  // -----------------------------------------------------------------------
  // YIN pitch detection  (simplified, no external deps)
  // -----------------------------------------------------------------------

  double? _yin(Float64List buf, int sampleRate) {
    final halfN = buf.length ~/ 2;

    // min/max lag → frequency range ~60-1000 Hz
    final minLag = math.max(2, sampleRate ~/ 1000);
    final maxLag = math.min(halfN - 1, sampleRate ~/ 60);

    // Step 1+2: cumulative mean normalized difference function
    final cmndf = Float64List(halfN);
    cmndf[0] = 1.0;
    double runningSum = 0;

    for (int tau = 1; tau < halfN; tau++) {
      double diff = 0;
      for (int i = 0; i < halfN; i++) {
        final d = buf[i] - buf[i + tau];
        diff += d * d;
      }
      runningSum += diff;
      cmndf[tau] = (runningSum > 0) ? diff * tau / runningSum : 1.0;
    }

    // Step 3: absolute threshold — find first dip below 0.15
    const threshold = 0.15;
    int bestTau = -1;

    for (int tau = minLag; tau <= maxLag; tau++) {
      if (cmndf[tau] < threshold) {
        // walk to the local minimum
        while (tau + 1 <= maxLag && cmndf[tau + 1] < cmndf[tau]) {
          tau++;
        }
        bestTau = tau;
        break;
      }
    }

    if (bestTau < 0) return null;

    // Step 4: parabolic interpolation for sub-sample accuracy
    if (bestTau > 0 && bestTau < halfN - 1) {
      final s0 = cmndf[bestTau - 1];
      final s1 = cmndf[bestTau];
      final s2 = cmndf[bestTau + 1];
      final denom = 2 * (s0 - 2 * s1 + s2);
      if (denom.abs() > 1e-12) {
        final shift = (s0 - s2) / denom;
        return sampleRate / (bestTau + shift);
      }
    }

    return sampleRate / bestTau.toDouble();
  }

  // -----------------------------------------------------------------------
  // Hz → note name
  // -----------------------------------------------------------------------

  static const _noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F',
    'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];

  String _hzToNote(double hz) {
    // semitones from A4 (440 Hz)
    final semitones = 12 * (math.log(hz / 440.0) / math.ln2);
    final midi = (semitones.round() + 69) % 12;
    return _noteNames[midi];
  }
}

class TunerResult {
  final double? frequency;
  final double rms;
  final String note;
  const TunerResult({required this.frequency, required this.rms, required this.note});
}

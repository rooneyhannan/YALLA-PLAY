import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:web_audio' as web_audio;

import 'audio_capture_base.dart';

AudioCaptureBase createAudioCapture() => WebAudioCapture();

class WebAudioCapture extends AudioCaptureBase {
  web_audio.AudioContext? _context;
  web_audio.ScriptProcessorNode? _processor;
  web_audio.GainNode? _gain;
  web_audio.MediaStreamAudioSourceNode? _source;
  html.MediaStream? _stream;
  StreamSubscription? _processSub;
  int _callbackCount = 0;

  @override
  Future<bool> init() async {
    print('[WebAudio] init() — browser platform, no native init needed');
    return true;
  }

  @override
  Future<void> start(
    AudioDataCallback onData,
    AudioErrorCallback onError, {
    int sampleRate = 44100,
    int bufferSize = 4096,
  }) async {
    try {
      // ---------------------------------------------------------------
      // 1. getUserMedia — triggers browser permission prompt
      // ---------------------------------------------------------------
      print('[WebAudio] Requesting getUserMedia({audio: true})...');

      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        print('[WebAudio] ERROR: navigator.mediaDevices is null (not HTTPS?)');
        onError(StateError('navigator.mediaDevices unavailable — HTTPS required'));
        return;
      }

      _stream = await mediaDevices.getUserMedia({'audio': true});
      final tracks = _stream!.getAudioTracks();
      print('[WebAudio] getUserMedia granted — ${tracks.length} audio track(s)');
      for (final t in tracks) {
        print('[WebAudio]   track: label="${t.label}", enabled=${t.enabled}, readyState=${t.readyState}');
      }

      // ---------------------------------------------------------------
      // 2. AudioContext — MUST be created/resumed during a user gesture
      // ---------------------------------------------------------------
      _context = web_audio.AudioContext();
      print('[WebAudio] AudioContext created — state=${_context!.state}, sampleRate=${_context!.sampleRate}');

      // Chrome autoplay policy: aggressively try to resume
      if (_context!.state != 'running') {
        print('[WebAudio] AudioContext not running (${_context!.state}), calling resume()...');
        await _context!.resume();
        // Give the browser a moment to transition
        await Future<void>.delayed(const Duration(milliseconds: 100));
        print('[WebAudio] AudioContext after resume(): state=${_context!.state}');
      }

      if (_context!.state != 'running') {
        print('[WebAudio] WARNING: AudioContext still not running (${_context!.state}). '
            'This usually means startListening() was NOT triggered by a user gesture.');
      }

      // ---------------------------------------------------------------
      // 3. Build the audio graph:
      //    mic → source → scriptProcessor → gain(0) → destination
      //
      //    gain(0) = muted so the mic is NOT played back through speakers,
      //    but the processor still fires onAudioProcess events.
      // ---------------------------------------------------------------
      _source = _context!.createMediaStreamSource(_stream!);
      print('[WebAudio] MediaStreamSource created');

      _processor = _context!.createScriptProcessor(bufferSize, 1, 1);
      print('[WebAudio] ScriptProcessorNode created (bufferSize=$bufferSize, in=1, out=1)');

      _gain = _context!.createGain();
      _gain!.gain!.value = 0;
      print('[WebAudio] GainNode created (gain=0, muted playback)');

      // Wire up the graph
      _source!.connectNode(_processor!);
      _processor!.connectNode(_gain!);
      _gain!.connectNode(_context!.destination!);
      print('[WebAudio] Audio graph connected: source → processor → gain(0) → destination');

      // ---------------------------------------------------------------
      // 4. Listen for audio data
      // ---------------------------------------------------------------
      _callbackCount = 0;

      _processSub = _processor!.onAudioProcess.listen((event) {
        _callbackCount++;
        final Float32List rawData = event.inputBuffer!.getChannelData(0);

        // --- Amplitude logging (first 5 then every 50th) ---
        if (_callbackCount <= 5 || _callbackCount % 50 == 0) {
          double sumSq = 0;
          double peak = 0;
          for (int i = 0; i < rawData.length; i++) {
            final v = rawData[i];
            sumSq += v * v;
            if (v.abs() > peak) peak = v.abs();
          }
          final rms = math.sqrt(sumSq / rawData.length);
          print('[WebAudio] onAudioProcess #$_callbackCount — '
              'len=${rawData.length}, RMS=${rms.toStringAsFixed(6)}, peak=${peak.toStringAsFixed(6)}');
        }

        // Copy the buffer (browser reuses the underlying ArrayBuffer)
        onData(Float32List.fromList(rawData));
      });

      print('[WebAudio] onAudioProcess listener registered — waiting for data...');
    } catch (e, st) {
      print('[WebAudio] ERROR in start(): $e');
      print('[WebAudio] Stack trace: $st');
      onError(e);
    }
  }

  @override
  Future<void> stop() async {
    print('[WebAudio] stop() called — total onAudioProcess callbacks: $_callbackCount');

    _processSub?.cancel();
    _processSub = null;

    _processor?.disconnect();
    _source?.disconnect();
    _gain?.disconnect();

    _stream?.getTracks().forEach((track) {
      print('[WebAudio] Stopping track: ${track.label}');
      track.stop();
    });

    if (_context != null && _context!.state != 'closed') {
      await _context!.close();
      print('[WebAudio] AudioContext closed');
    }

    _context = null;
    _processor = null;
    _source = null;
    _gain = null;
    _stream = null;
  }
}

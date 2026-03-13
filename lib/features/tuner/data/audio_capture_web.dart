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
  int _actualSampleRate = 44100;

  /// Periodic timer that checks AudioContext health and auto-resumes.
  Timer? _healthTimer;

  /// Stored callbacks so the health-check can report errors.
  AudioErrorCallback? _onError;

  @override
  int get actualSampleRate => _actualSampleRate;

  @override
  Future<bool> init() async {
    print('[WebAudio] init() — browser platform');
    return true;
  }

  @override
  Future<void> start(
    AudioDataCallback onData,
    AudioErrorCallback onError, {
    int sampleRate = 44100,
    int bufferSize = 4096,
  }) async {
    _onError = onError;

    try {
      // ---------------------------------------------------------------
      // 1. getUserMedia
      // ---------------------------------------------------------------
      print('[WebAudio] Requesting getUserMedia({audio: true})...');

      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        final msg = 'navigator.mediaDevices is null — HTTPS required for mic access';
        print('[WebAudio] ERROR: $msg');
        onError(StateError(msg));
        return;
      }

      _stream = await mediaDevices.getUserMedia({'audio': true});
      final tracks = _stream!.getAudioTracks();
      print('[WebAudio] getUserMedia granted — ${tracks.length} audio track(s)');
      for (final t in tracks) {
        print('[WebAudio]   track: label="${t.label}", '
            'enabled=${t.enabled}, readyState=${t.readyState}');
      }

      // Listen for tracks ending unexpectedly (headphones unplugged, etc.)
      for (final t in tracks) {
        t.onEnded.listen((_) {
          print('[WebAudio] WARNING: audio track "${t.label}" ended unexpectedly');
          onError(StateError('Audio track ended: ${t.label}'));
        });
      }

      // ---------------------------------------------------------------
      // 2. AudioContext — adapt to hardware sample rate
      // ---------------------------------------------------------------
      _context = web_audio.AudioContext();
      _actualSampleRate = _context!.sampleRate?.toInt() ?? sampleRate;
      print('[WebAudio] AudioContext created — '
          'state=${_context!.state}, '
          'hardwareSampleRate=$_actualSampleRate');

      // Chrome autoplay policy: resume if not running
      await _ensureContextRunning();

      // ---------------------------------------------------------------
      // 3. Build the audio graph:
      //    mic → source → scriptProcessor → gain(0) → destination
      // ---------------------------------------------------------------
      _source = _context!.createMediaStreamSource(_stream!);
      print('[WebAudio] MediaStreamSource created');

      _processor = _context!.createScriptProcessor(bufferSize, 1, 1);
      print('[WebAudio] ScriptProcessorNode created (bufferSize=$bufferSize)');

      _gain = _context!.createGain();
      _gain!.gain!.value = 0;

      // Wire the graph
      _source!.connectNode(_processor!);
      _processor!.connectNode(_gain!);
      _gain!.connectNode(_context!.destination!);
      print('[WebAudio] Audio graph: source → processor → gain(0) → destination');

      // ---------------------------------------------------------------
      // 4. Listen for audio data — with full error protection
      // ---------------------------------------------------------------
      _callbackCount = 0;

      _processSub = _processor!.onAudioProcess.listen(
        // --- onData ---
        (web_audio.AudioProcessingEvent event) {
          try {
            _callbackCount++;
            final inputBuffer = event.inputBuffer;
            if (inputBuffer == null) {
              if (_callbackCount <= 3) {
                print('[WebAudio] WARNING: inputBuffer is null (cb #$_callbackCount)');
              }
              return;
            }

            final Float32List rawData = inputBuffer.getChannelData(0);

            // Amplitude logging: first 5, then every 50th
            if (_callbackCount <= 5 || _callbackCount % 50 == 0) {
              double sumSq = 0;
              double peak = 0;
              for (int i = 0; i < rawData.length; i++) {
                final v = rawData[i];
                sumSq += v * v;
                final abs = v.abs();
                if (abs > peak) peak = abs;
              }
              final rms = math.sqrt(sumSq / rawData.length);
              print('[WebAudio] cb #$_callbackCount — '
                  'len=${rawData.length}, '
                  'RMS=${rms.toStringAsFixed(6)}, '
                  'peak=${peak.toStringAsFixed(6)}');
            }

            // Copy the buffer (browser reuses the underlying ArrayBuffer)
            onData(Float32List.fromList(rawData));
          } catch (e) {
            // CRITICAL: catch here so a single bad frame doesn't kill the stream
            print('[WebAudio] ERROR in onAudioProcess cb #$_callbackCount: $e');
          }
        },
        // --- onError on the stream itself ---
        onError: (Object error) {
          print('[WebAudio] onAudioProcess stream error: $error');
          onError(error);
        },
        // --- onDone (stream closed unexpectedly) ---
        onDone: () {
          print('[WebAudio] onAudioProcess stream done (closed). '
              'Total callbacks: $_callbackCount');
          if (_callbackCount == 0) {
            onError(StateError(
                'ScriptProcessorNode stream closed without delivering any data. '
                'The browser may not support this API.'));
          }
        },
        cancelOnError: false, // keep listening even after errors
      );

      print('[WebAudio] onAudioProcess listener registered — waiting for data...');

      // ---------------------------------------------------------------
      // 5. Health check timer: auto-resume suspended AudioContext
      // ---------------------------------------------------------------
      _healthTimer?.cancel();
      _healthTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _healthCheck();
      });

      print('[WebAudio] Health-check timer started (every 2s)');
    } catch (e, st) {
      print('[WebAudio] ERROR in start(): $e');
      print('[WebAudio] $st');
      onError(e);
    }
  }

  /// Tries to bring the AudioContext to 'running' state.
  Future<void> _ensureContextRunning() async {
    if (_context == null) return;
    final state = _context!.state;
    if (state == 'running') return;

    print('[WebAudio] AudioContext state="$state", calling resume()...');
    try {
      await _context!.resume();
      // Give the browser a moment to transition
      await Future<void>.delayed(const Duration(milliseconds: 150));
      print('[WebAudio] AudioContext after resume(): state=${_context!.state}');
    } catch (e) {
      print('[WebAudio] resume() failed: $e');
    }

    if (_context!.state != 'running') {
      print('[WebAudio] WARNING: AudioContext still "${_context!.state}" after resume(). '
          'Ensure startListening() is triggered by a user gesture (tap/click).');
    }
  }

  /// Periodic health check: auto-resume if context got suspended/interrupted.
  void _healthCheck() {
    if (_context == null) return;

    final state = _context!.state;
    if (state == 'running') return;

    if (state == 'closed') {
      print('[WebAudio] HEALTH: AudioContext is closed — stream is dead');
      _onError?.call(StateError('AudioContext was closed'));
      _healthTimer?.cancel();
      return;
    }

    // suspended or interrupted — try to revive
    print('[WebAudio] HEALTH: AudioContext state="$state", attempting resume()...');
    _context!.resume().then((_) {
      print('[WebAudio] HEALTH: resume() complete, state=${_context?.state}');
    }).catchError((Object e) {
      print('[WebAudio] HEALTH: resume() failed: $e');
    });
  }

  @override
  Future<void> stop() async {
    print('[WebAudio] stop() called — total callbacks: $_callbackCount');

    _healthTimer?.cancel();
    _healthTimer = null;

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
      try {
        await _context!.close();
        print('[WebAudio] AudioContext closed');
      } catch (e) {
        print('[WebAudio] AudioContext.close() error: $e');
      }
    }

    _context = null;
    _processor = null;
    _source = null;
    _gain = null;
    _stream = null;
    _onError = null;
  }
}

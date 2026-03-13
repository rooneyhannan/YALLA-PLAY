import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';

import 'audio_capture.dart';
import 'audio_capture_base.dart';

enum MicStatus { inactive, requesting, denied, active, error }

class AudioManager {
  AudioManager._();
  static final AudioManager instance = AudioManager._();

  late final AudioCaptureBase _audioCapture = createAudioCapture();

  static const int _bufferSize = 4096;

  /// Created lazily with the actual hardware sample rate.
  PitchDetector? _pitchDetector;
  int _activeSampleRate = 0;

  bool _listening = false;
  bool _processing = false;
  int _bufferCount = 0;
  int _pitchHitCount = 0;

  /// Stored so self-healing can restart with the same callback.
  void Function(double freq)? _onPitchDetected;

  /// Watchdog: detects stalled audio streams.
  Timer? _watchdog;
  int _lastWatchdogBufferCount = 0;
  int _restartAttempts = 0;
  static const int _maxRestartAttempts = 3;

  final ValueNotifier<MicStatus> micStatus =
      ValueNotifier<MicStatus>(MicStatus.inactive);

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /// Call from a user-gesture handler (tap/click) so the browser allows
  /// AudioContext activation.
  Future<void> startListening(void Function(double freq) onPitchDetected) async {
    if (_listening) {
      print('[AudioManager] already listening — ignoring');
      return;
    }

    _onPitchDetected = onPitchDetected;
    print('[AudioManager] startListening()');
    micStatus.value = MicStatus.requesting;

    try {
      final ok = await _audioCapture.init();
      print('[AudioManager] init() => $ok');
      if (!ok) {
        micStatus.value = MicStatus.denied;
        return;
      }

      _listening = true;
      _bufferCount = 0;
      _pitchHitCount = 0;
      _restartAttempts = 0;
      micStatus.value = MicStatus.active;

      await _startCapture(onPitchDetected);
    } catch (e, st) {
      print('[AudioManager] startListening() error: $e\n$st');
      micStatus.value = MicStatus.error;
      unawaited(stopListening());
    }
  }

  Future<void> stopListening() async {
    if (!_listening) return;
    print('[AudioManager] stopListening() — '
        'buffers=$_bufferCount, pitchHits=$_pitchHitCount');
    _listening = false;
    _processing = false;
    _watchdog?.cancel();
    _watchdog = null;
    _onPitchDetected = null;
    await _audioCapture.stop();
    micStatus.value = MicStatus.inactive;
  }

  // -----------------------------------------------------------------------
  // Internal: start capture + watchdog
  // -----------------------------------------------------------------------

  Future<void> _startCapture(void Function(double freq) onPitchDetected) async {
    await _audioCapture.start(
      // ---------- onData ----------
      (Float32List buffer) {
        _bufferCount++;

        if (_processing) return;
        _processing = true;

        _processBuffer(buffer, onPitchDetected).whenComplete(() {
          _processing = false;
        });
      },

      // ---------- onError ----------
      (Object error) {
        print('[AudioManager] capture error: $error');
        _handleStreamDeath('capture error: $error');
      },

      sampleRate: 44100, // hint; web ignores this and uses hardware rate
      bufferSize: _bufferSize,
    );

    // Create / re-create PitchDetector with the actual hardware sample rate
    final hwRate = _audioCapture.actualSampleRate;
    if (_pitchDetector == null || _activeSampleRate != hwRate) {
      _activeSampleRate = hwRate;
      _pitchDetector = PitchDetector(
        audioSampleRate: hwRate.toDouble(),
        bufferSize: _bufferSize,
      );
      print('[AudioManager] PitchDetector created — '
          'sampleRate=$hwRate, bufferSize=$_bufferSize');
    }

    print('[AudioManager] capture started (hw sampleRate=$hwRate)');

    // Start watchdog
    _lastWatchdogBufferCount = _bufferCount;
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 3), (_) {
      _watchdogCheck();
    });
  }

  // -----------------------------------------------------------------------
  // Pitch processing with NaN / Infinity / null guards
  // -----------------------------------------------------------------------

  Future<void> _processBuffer(
    Float32List buffer,
    void Function(double freq) onPitchDetected,
  ) async {
    try {
      final detector = _pitchDetector;
      if (detector == null) return;

      final result = await detector.getPitchFromFloatBuffer(buffer.toList());

      // Log first few + periodic
      if (_bufferCount <= 5 || _bufferCount % 100 == 0) {
        print('[AudioManager] buf #$_bufferCount — '
            'pitched=${result.pitched}, '
            'pitch=${result.pitch}, '
            'prob=${result.probability}');
      }

      // Guard: pitched must be true
      if (!result.pitched) return;

      final pitch = result.pitch;

      // Guard: reject NaN, Infinity, zero, negative
      if (pitch.isNaN || pitch.isInfinite || pitch <= 0) {
        print('[AudioManager] WARNING: invalid pitch value: $pitch (skipped)');
        return;
      }

      // Guard: reasonable frequency range for instruments
      if (pitch < 20 || pitch > 2000) return;

      _pitchHitCount++;
      if (_pitchHitCount <= 5 || _pitchHitCount % 50 == 0) {
        print('[AudioManager] pitch #$_pitchHitCount → '
            '${pitch.toStringAsFixed(1)} Hz');
      }
      onPitchDetected(pitch);
    } catch (e) {
      print('[AudioManager] pitch processing error: $e');
    }
  }

  // -----------------------------------------------------------------------
  // Watchdog: detect stalled streams and auto-restart
  // -----------------------------------------------------------------------

  void _watchdogCheck() {
    if (!_listening) return;

    if (_bufferCount == _lastWatchdogBufferCount) {
      // No new buffers in the last 3 seconds — stream is stalled
      print('[AudioManager] WATCHDOG: stream stalled '
          '(stuck at buffer #$_bufferCount for 3s)');
      _handleStreamDeath('stalled — no audio data for 3 seconds');
    } else {
      _lastWatchdogBufferCount = _bufferCount;
    }
  }

  // -----------------------------------------------------------------------
  // Self-healing: restart the capture pipeline
  // -----------------------------------------------------------------------

  void _handleStreamDeath(String reason) {
    if (!_listening) return;

    _restartAttempts++;
    print('[AudioManager] Stream died: $reason '
        '(restart attempt $_restartAttempts/$_maxRestartAttempts)');

    if (_restartAttempts > _maxRestartAttempts) {
      print('[AudioManager] Max restart attempts reached — giving up');
      micStatus.value = MicStatus.error;
      unawaited(stopListening());
      return;
    }

    // Tear down current capture, then restart after a brief delay
    final callback = _onPitchDetected;
    if (callback == null) {
      print('[AudioManager] No callback stored — cannot restart');
      micStatus.value = MicStatus.error;
      unawaited(stopListening());
      return;
    }

    _watchdog?.cancel();
    _processing = false;

    // Stop the current capture (but keep _listening = true)
    _audioCapture.stop().then((_) {
      final delay = Duration(milliseconds: 500 * _restartAttempts);
      print('[AudioManager] Restarting in ${delay.inMilliseconds}ms...');

      Timer(delay, () {
        if (!_listening) return; // user stopped while waiting
        print('[AudioManager] Restarting capture (attempt $_restartAttempts)...');
        micStatus.value = MicStatus.requesting;
        _audioCapture.init().then((ok) {
          if (!ok || !_listening) {
            micStatus.value = MicStatus.error;
            return;
          }
          micStatus.value = MicStatus.active;
          _startCapture(callback);
        }).catchError((Object e) {
          print('[AudioManager] Restart init failed: $e');
          micStatus.value = MicStatus.error;
        });
      });
    }).catchError((Object e) {
      print('[AudioManager] Restart stop() failed: $e');
    });
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'audio_capture.dart';
import 'audio_capture_base.dart';

// Lazy-import so pitch_detector_dart is not loaded until needed.
import 'package:pitch_detector_dart/pitch_detector.dart';

enum MicStatus { inactive, requesting, denied, active, error }

class AudioManager {
  AudioManager._();
  static final AudioManager instance = AudioManager._();

  late final AudioCaptureBase _audioCapture = createAudioCapture();

  static const int _sampleRate = 44100;
  static const int _bufferSize = 4096;

  late final PitchDetector _pitchDetector = PitchDetector(
    audioSampleRate: _sampleRate.toDouble(),
    bufferSize: _bufferSize,
  );

  bool _listening = false;
  bool _processing = false;
  int _bufferCount = 0;
  int _pitchHitCount = 0;

  final ValueNotifier<MicStatus> micStatus =
      ValueNotifier<MicStatus>(MicStatus.inactive);

  /// Call this from a user-gesture handler (tap / click) so the browser
  /// allows AudioContext activation.
  Future<void> startListening(
      void Function(double freq) onPitchDetected) async {
    if (_listening) {
      print('[AudioManager] already listening — ignoring duplicate call');
      return;
    }

    print('[AudioManager] startListening() called');
    micStatus.value = MicStatus.requesting;

    try {
      final ok = await _audioCapture.init();
      print('[AudioManager] _audioCapture.init() => $ok');
      if (!ok) {
        micStatus.value = MicStatus.denied;
        return;
      }

      _listening = true;
      _bufferCount = 0;
      _pitchHitCount = 0;
      micStatus.value = MicStatus.active;
      print('[AudioManager] micStatus → active, starting capture...');

      await _audioCapture.start(
        // ---------- onData ----------
        (Float32List buffer) async {
          _bufferCount++;

          if (_processing) return;
          _processing = true;

          try {
            final result = await _pitchDetector
                .getPitchFromFloatBuffer(buffer.toList());

            // Log first few results + every 100th for ongoing monitoring
            if (_bufferCount <= 5 || _bufferCount % 100 == 0) {
              print('[AudioManager] buffer #$_bufferCount — '
                  'pitched=${result.pitched}, '
                  'pitch=${result.pitch.toStringAsFixed(1)}, '
                  'prob=${result.probability.toStringAsFixed(3)}');
            }

            if (result.pitched &&
                result.pitch > 20 &&
                result.pitch < 2000) {
              _pitchHitCount++;
              if (_pitchHitCount <= 5 || _pitchHitCount % 50 == 0) {
                print('[AudioManager] ✓ pitch #$_pitchHitCount → '
                    '${result.pitch.toStringAsFixed(1)} Hz');
              }
              onPitchDetected(result.pitch);
            }
          } catch (e) {
            print('[AudioManager] pitch-detection error: $e');
          } finally {
            _processing = false;
          }
        },

        // ---------- onError ----------
        (Object error) {
          print('[AudioManager] capture error callback: $error');
          micStatus.value = MicStatus.error;
          unawaited(stopListening());
        },

        sampleRate: _sampleRate,
        bufferSize: _bufferSize,
      );

      print('[AudioManager] capture.start() completed (stream is running)');
    } catch (e, st) {
      print('[AudioManager] startListening() threw: $e\n$st');
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
    await _audioCapture.stop();
    micStatus.value = MicStatus.inactive;
  }
}

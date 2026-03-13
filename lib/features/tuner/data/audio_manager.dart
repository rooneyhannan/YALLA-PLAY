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

  static const int _sampleRate = 44100;
  static const int _bufferSize = 4096;

  final PitchDetector _pitchDetector = PitchDetector(
    audioSampleRate: _sampleRate.toDouble(),
    bufferSize: _bufferSize,
  );

  bool _listening = false;
  bool _processing = false;

  final ValueNotifier<MicStatus> micStatus =
      ValueNotifier<MicStatus>(MicStatus.inactive);

  Future<void> startListening(
      void Function(double freq) onPitchDetected) async {
    if (_listening) return;

    micStatus.value = MicStatus.requesting;

    try {
      final ok = await _audioCapture.init();
      if (!ok) {
        micStatus.value = MicStatus.denied;
        return;
      }

      _listening = true;
      micStatus.value = MicStatus.active;

      await _audioCapture.start(
        (Float32List buffer) async {
          if (_processing) return;
          _processing = true;
          try {
            final result =
                await _pitchDetector.getPitchFromFloatBuffer(buffer.toList());

            if (result.pitched &&
                result.pitch > 20 &&
                result.pitch < 2000) {
              onPitchDetected(result.pitch);
            }
          } catch (e) {
            debugPrint('AudioManager pitch error: $e');
          } finally {
            _processing = false;
          }
        },
        (Object error) {
          debugPrint('AudioManager capture error: $error');
          micStatus.value = MicStatus.error;
          unawaited(stopListening());
        },
        sampleRate: _sampleRate,
        bufferSize: _bufferSize,
      );
    } catch (e) {
      debugPrint('AudioManager start error: $e');
      micStatus.value = MicStatus.error;
      unawaited(stopListening());
    }
  }

  Future<void> stopListening() async {
    if (!_listening) return;
    _listening = false;
    _processing = false;
    await _audioCapture.stop();
    micStatus.value = MicStatus.inactive;
  }
}

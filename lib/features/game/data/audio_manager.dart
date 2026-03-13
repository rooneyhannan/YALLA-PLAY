import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_audio_capture/flutter_audio_capture.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';

class AudioManager {
  AudioManager._();
  static final AudioManager instance = AudioManager._();

  final FlutterAudioCapture _audioCapture = FlutterAudioCapture();

  // Keep buffer sizes aligned across capture + detector.
  static const int _sampleRate = 44100;
  static const int _bufferSize = 4096;

  final PitchDetector _pitchDetector = PitchDetector(
    audioSampleRate: _sampleRate.toDouble(),
    bufferSize: _bufferSize,
  );

  bool _initialized = false;
  bool _listening = false;
  bool _processing = false;
  int _audioCallbackCount = 0;

  Future<void> startListening(void Function(double freq) onPitchDetected) async {
    print('DEBUG: Asking for permission...');
    // Permissions
    final status = await Permission.microphone.request();
    print('DEBUG: Permission status: $status');
    if (!status.isGranted) {
      print('DEBUG: Microphone permission not granted, aborting startListening().');
      return;
    }

    try {
      // Init capture once
      if (!_initialized) {
        print('DEBUG: Initializing FlutterAudioCapture...');
        final ok = await _audioCapture.init();
        print('DEBUG: FlutterAudioCapture.init() => $ok');
        if (ok != true) return;
        _initialized = true;
      }

      if (_listening) {
        print('DEBUG: Already listening, ignoring startListening() call.');
        return;
      }

      print('DEBUG: Starting audio capture (sampleRate=$_sampleRate, bufferSize=$_bufferSize)...');
      _audioCallbackCount = 0;
      _listening = true;

      await _audioCapture.start(
        (Float32List buffer) async {
          _audioCallbackCount++;
          if (_audioCallbackCount % 100 == 0) {
            print('DEBUG: Audio data received (count=$_audioCallbackCount, len=${buffer.length})');
          }

          // Prevent overlapping async pitch computations (keeps UI stable)
          if (_processing) return;
          _processing = true;
          try {
            final pitchResult =
                await _pitchDetector.getPitchFromFloatBuffer(buffer.toList());

            if (pitchResult.pitched) {
              print(
                  'DEBUG: Pitch detected: pitch=${pitchResult.pitch}, probability=${pitchResult.probability}, pitched=${pitchResult.pitched}');

              // Basic sanity filter; guitar fundamentals usually live < 1kHz
              if (pitchResult.pitch > 20 && pitchResult.pitch < 2000) {
                onPitchDetected(pitchResult.pitch);
              }
            }
          } catch (e) {
            print('DEBUG ERROR: $e');
          } finally {
            _processing = false;
          }
        },
        (Object error) {
          print('DEBUG ERROR: flutter_audio_capture error: $error');
          // Stop if capture fails
          unawaited(stopListening());
        },
        sampleRate: _sampleRate,
        bufferSize: _bufferSize,
        // Prefer mic input on Android for tuning use-case
        androidAudioSource: ANDROID_AUDIOSRC_MIC,
      );
    } catch (e) {
      print('DEBUG ERROR: $e');
      // Best-effort cleanup if start throws
      unawaited(stopListening());
    }
  }

  Future<void> stopListening() async {
    if (!_listening) return;
    print('DEBUG: Stopping audio capture...');
    _listening = false;
    _processing = false;
    await _audioCapture.stop();
    print('DEBUG: Audio capture stopped.');
  }
}


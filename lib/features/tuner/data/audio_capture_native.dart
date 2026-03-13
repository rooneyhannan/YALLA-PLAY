import 'dart:typed_data';

import 'package:flutter_audio_capture/flutter_audio_capture.dart';
import 'package:permission_handler/permission_handler.dart';

import 'audio_capture_base.dart';

AudioCaptureBase createAudioCapture() => NativeAudioCapture();

class NativeAudioCapture extends AudioCaptureBase {
  final FlutterAudioCapture _capture = FlutterAudioCapture();
  bool _initialized = false;
  int _actualSampleRate = 44100;

  @override
  int get actualSampleRate => _actualSampleRate;

  @override
  Future<bool> init() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) return false;

    if (!_initialized) {
      final ok = await _capture.init();
      if (ok != true) return false;
      _initialized = true;
    }
    return true;
  }

  @override
  Future<void> start(
    AudioDataCallback onData,
    AudioErrorCallback onError, {
    int sampleRate = 44100,
    int bufferSize = 4096,
  }) async {
    _actualSampleRate = sampleRate;
    await _capture.start(
      (Float32List buffer) async => onData(buffer),
      (Object error) => onError(error),
      sampleRate: sampleRate,
      bufferSize: bufferSize,
      androidAudioSource: ANDROID_AUDIOSRC_MIC,
    );
  }

  @override
  Future<void> stop() async {
    await _capture.stop();
  }
}

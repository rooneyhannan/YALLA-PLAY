import 'dart:typed_data';

typedef AudioDataCallback = void Function(Float32List buffer);
typedef AudioErrorCallback = void Function(Object error);

/// Platform-agnostic interface for microphone audio capture.
abstract class AudioCaptureBase {
  Future<bool> init();

  Future<void> start(
    AudioDataCallback onData,
    AudioErrorCallback onError, {
    int sampleRate = 44100,
    int bufferSize = 4096,
  });

  Future<void> stop();
}

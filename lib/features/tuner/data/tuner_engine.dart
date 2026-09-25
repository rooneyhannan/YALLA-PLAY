import 'tuner_engine_stub.dart'
    if (dart.library.js_interop) 'tuner_engine_web.dart'
    as platform;

/// Receives a detected pitch in Hz, or null while nothing clear is heard.
/// [level] is the RMS input level from 0 to 1.
typedef PitchCallback = void Function(double? frequency, double level);

/// Listens to the microphone and reports pitches until [stop] is called.
abstract class TunerEngine {
  /// Must be called from a user gesture (a tap), or browsers keep the audio
  /// context suspended. Throws a [TunerException] when listening fails.
  Future<void> start(PitchCallback onPitch);
  void stop();
}

TunerEngine createTunerEngine() => platform.createPlatformTunerEngine();

enum TunerError { permissionDenied, noMicrophone, unsupported, failed }

class TunerException implements Exception {
  final TunerError error;
  final String detail;
  const TunerException(this.error, [this.detail = '']);
  @override
  String toString() => 'TunerException($error, $detail)';
}

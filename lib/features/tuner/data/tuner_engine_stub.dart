import 'tuner_engine.dart';

// Microphone capture is implemented for the web build only.
TunerEngine createPlatformTunerEngine() => _UnsupportedTunerEngine();

class _UnsupportedTunerEngine implements TunerEngine {
  @override
  Future<void> start(PitchCallback onPitch) async =>
      throw const TunerException(TunerError.unsupported);

  @override
  void stop() {}
}

import 'sound_engine.dart';
import 'synth.dart';

// Sound output is implemented for the web build only for now.
SoundEngine createPlatformSoundEngine() => _SilentSoundEngine();

class _SilentSoundEngine implements SoundEngine {
  @override
  Future<void> start() async {}

  @override
  double? get time => null;

  @override
  void play(
    Voice voice,
    double frequency, {
    required double at,
    required double length,
    required double gain,
  }) {}

  @override
  void silence() {}

  @override
  void dispose() {}
}

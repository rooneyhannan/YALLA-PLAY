import 'sound_engine_stub.dart'
    if (dart.library.js_interop) 'sound_engine_web.dart'
    as platform;
import 'synth.dart';

/// Plays the sounds of the play screen at exact times of its own clock.
abstract class SoundEngine {
  /// Must be called from a user gesture (a tap), or browsers keep the audio
  /// muted. Never throws; without sound the game still runs.
  Future<void> start();

  /// The audio clock in seconds, or null while there is no sound.
  double? get time;

  /// Plays [voice] at [frequency] from [at] on the clock for [length]
  /// seconds, then fades it out.
  void play(
    Voice voice,
    double frequency, {
    required double at,
    required double length,
    required double gain,
  });

  /// Stops everything playing or scheduled.
  void silence();

  void dispose();
}

SoundEngine createSoundEngine() => platform.createPlatformSoundEngine();

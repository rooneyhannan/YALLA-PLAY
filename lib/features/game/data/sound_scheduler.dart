import 'arrangement.dart';
import 'sound_engine.dart';

/// Hands the arrangement's events to the sound engine a little ahead of
/// time, mapping song ticks to the audio clock.
class SoundScheduler {
  final List<SoundEvent> events;
  int _next = 0;
  SoundScheduler(this.events);

  /// Continues from [tick]: events before it are skipped.
  void seek(double tick) {
    _next = 0;
    while (_next < events.length && events[_next].tick < tick - 1e-6) {
      _next++;
    }
  }

  /// Schedules the events up to [until]. The song is at [tick] when the
  /// audio clock reads [now].
  void run(
    SoundEngine engine, {
    required double tick,
    required double until,
    required double now,
    required double ticksPerSecond,
    required bool Function(SoundEvent) enabled,
  }) {
    while (_next < events.length && events[_next].tick <= until) {
      final e = events[_next++];
      if (!enabled(e)) continue;
      final delay = (e.tick - tick) / ticksPerSecond;
      engine.play(
        e.voice,
        e.frequency,
        at: now + (delay > 0 ? delay : 0),
        length: e.length / ticksPerSecond,
        gain: e.gain,
      );
    }
  }
}

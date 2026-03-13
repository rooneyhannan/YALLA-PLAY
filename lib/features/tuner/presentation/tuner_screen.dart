import 'package:flutter/material.dart';
import '../data/audio_manager.dart';

class TunerScreen extends StatefulWidget {
  const TunerScreen({super.key});

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen>
    with SingleTickerProviderStateMixin {
  // Standard guitar tuning targets
  static const List<_GuitarString> _strings = [
    _GuitarString(code: 'E2', name: 'E', hz: 82.41),
    _GuitarString(code: 'A2', name: 'A', hz: 110.00),
    _GuitarString(code: 'D3', name: 'D', hz: 146.83),
    _GuitarString(code: 'G3', name: 'G', hz: 196.00),
    _GuitarString(code: 'B3', name: 'B', hz: 246.94),
    _GuitarString(code: 'E4', name: 'E', hz: 329.63),
  ];

  // UI State
  double? _frequency;
  int? _activeStringIndex;
  String _noteName = '--';
  String _statusText = 'Tap mic to start';
  double _diffHz = 0.0;

  // Throttle UI updates
  DateTime _lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minUiInterval = Duration(milliseconds: 60);

  // Mic pulse animation
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Listen to mic status changes
    AudioManager.instance.micStatus.addListener(_onMicStatusChanged);

    // Do NOT auto-start here!  Chrome's autoplay policy requires that the
    // AudioContext is created/resumed inside a user-gesture callback (tap).
    // The user taps the mic indicator (_toggleListening) to begin.
  }

  void _onMicStatusChanged() {
    if (!mounted) return;
    final status = AudioManager.instance.micStatus.value;
    setState(() {
      if (status == MicStatus.active) {
        _pulseController.repeat(reverse: true);
        _statusText = 'Listening...';
      } else {
        _pulseController.stop();
        _pulseController.reset();
        if (status == MicStatus.denied) {
          _statusText = 'Mic permission denied';
        } else if (status == MicStatus.error) {
          _statusText = 'Mic error';
        } else if (status == MicStatus.requesting) {
          _statusText = 'Requesting mic...';
        }
      }
    });
  }

  void _onPitchDetected(double freq) {
    if (!mounted) return;

    if (freq <= 0) {
      final now = DateTime.now();
      if (now.difference(_lastUiUpdate) < _minUiInterval) return;
      _lastUiUpdate = now;
      setState(() {
        _frequency = null;
        _activeStringIndex = null;
        _noteName = '--';
        _statusText = 'Listening...';
        _diffHz = 0.0;
      });
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastUiUpdate) < _minUiInterval) return;
    _lastUiUpdate = now;

    final mapped = _mapToClosestString(freq);
    setState(() {
      _frequency = freq;
      _activeStringIndex = mapped.index;
      _noteName = mapped.string.name;
      _diffHz = mapped.diffHz;

      if (mapped.diffHz.abs() <= 2.0) {
        _statusText = 'Tuned';
      } else if (mapped.diffHz < 0) {
        _statusText = 'Too Low';
      } else {
        _statusText = 'Too High';
      }
    });
  }

  _MappedString _mapToClosestString(double freq) {
    int bestIndex = 0;
    double bestDiff = (freq - _strings[0].hz).abs();
    for (int i = 1; i < _strings.length; i++) {
      final d = (freq - _strings[i].hz).abs();
      if (d < bestDiff) {
        bestDiff = d;
        bestIndex = i;
      }
    }
    final target = _strings[bestIndex];
    return _MappedString(
      index: bestIndex,
      string: target,
      diffHz: freq - target.hz,
    );
  }

  void _toggleListening() {
    final status = AudioManager.instance.micStatus.value;
    if (status == MicStatus.active) {
      AudioManager.instance.stopListening();
      setState(() {
        _frequency = null;
        _activeStringIndex = null;
        _noteName = '--';
        _statusText = 'Tap mic to start';
        _diffHz = 0.0;
      });
    } else if (status == MicStatus.inactive ||
        status == MicStatus.denied ||
        status == MicStatus.error) {
      AudioManager.instance.startListening(_onPitchDetected);
    }
  }

  @override
  void dispose() {
    AudioManager.instance.micStatus.removeListener(_onMicStatusChanged);
    _pulseController.dispose();
    AudioManager.instance.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final freqText =
        _frequency == null ? '-- Hz' : '${_frequency!.toStringAsFixed(1)} Hz';

    final bool tuned = _statusText == 'Tuned';
    final Color accent = tuned ? const Color(0xFF00E676) : Colors.redAccent;

    final double needle =
        _frequency == null ? 0.0 : (_diffHz / 10.0).clamp(-1.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              // Mic status indicator
              _MicIndicator(
                micStatus: AudioManager.instance.micStatus,
                pulseAnimation: _pulseAnimation,
                onTap: _toggleListening,
              ),

              const SizedBox(height: 16),

              // Top: String circles
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(_strings.length, (i) {
                  final s = _strings[i];
                  final bool active = _activeStringIndex == i;
                  final bool isTunedActive = active && tuned;
                  final Color ringColor = isTunedActive
                      ? const Color(0xFF00E676)
                      : (active ? Colors.white : Colors.white24);

                  return _StringCircle(
                    label: s.code,
                    active: active,
                    ringColor: ringColor,
                    fillColor: active
                        ? Colors.white.withOpacity(0.08)
                        : Colors.white.withOpacity(0.03),
                  );
                }),
              ),

              const SizedBox(height: 40),

              // Center: Note
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _noteName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 120,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _statusText,
                      style: TextStyle(
                        color: tuned ? const Color(0xFF00E676) : Colors.white70,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Needle / bar
                    _TunerNeedle(
                      value: needle,
                      accent: accent,
                      tuned: tuned,
                    ),
                  ],
                ),
              ),

              // Bottom: Frequency
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  freqText,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper data classes
// ---------------------------------------------------------------------------

class _GuitarString {
  final String code;
  final String name;
  final double hz;
  const _GuitarString(
      {required this.code, required this.name, required this.hz});
}

class _MappedString {
  final int index;
  final _GuitarString string;
  final double diffHz;
  const _MappedString(
      {required this.index, required this.string, required this.diffHz});
}

// ---------------------------------------------------------------------------
// Mic status indicator widget
// ---------------------------------------------------------------------------

class _MicIndicator extends StatelessWidget {
  final ValueNotifier<MicStatus> micStatus;
  final Animation<double> pulseAnimation;
  final VoidCallback onTap;

  const _MicIndicator({
    required this.micStatus,
    required this.pulseAnimation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MicStatus>(
      valueListenable: micStatus,
      builder: (context, status, _) {
        final bool active = status == MicStatus.active;
        final bool denied = status == MicStatus.denied;
        final bool error = status == MicStatus.error;
        final bool requesting = status == MicStatus.requesting;

        final Color dotColor = active
            ? const Color(0xFF00E676)
            : (denied || error)
                ? Colors.redAccent
                : requesting
                    ? Colors.amber
                    : Colors.white38;

        final String label = active
            ? 'MIC ACTIVE'
            : denied
                ? 'MIC DENIED'
                : error
                    ? 'MIC ERROR'
                    : requesting
                        ? 'REQUESTING...'
                        : 'MIC OFF';

        final IconData icon = denied
            ? Icons.mic_off_rounded
            : Icons.mic_rounded;

        return GestureDetector(
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (active)
                ScaleTransition(
                  scale: pulseAnimation,
                  child: Icon(icon, color: dotColor, size: 22),
                )
              else
                Icon(icon, color: dotColor, size: 22),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: dotColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// String circle widget
// ---------------------------------------------------------------------------

class _StringCircle extends StatelessWidget {
  final String label;
  final bool active;
  final Color ringColor;
  final Color fillColor;

  const _StringCircle({
    required this.label,
    required this.active,
    required this.ringColor,
    required this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fillColor,
        border: Border.all(color: ringColor, width: active ? 2.5 : 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.white : Colors.white54,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tuner needle widget
// ---------------------------------------------------------------------------

class _TunerNeedle extends StatelessWidget {
  final double value;
  final Color accent;
  final bool tuned;

  const _TunerNeedle({
    required this.value,
    required this.accent,
    required this.tuned,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final centerX = w / 2;
                final needleX = centerX + (value * (w / 2 - 6));

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Base bar
                    Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),

                    // Center mark
                    Positioned(
                      left: centerX - 1,
                      child: Container(
                        width: 2,
                        height: 22,
                        decoration: BoxDecoration(
                          color: tuned
                              ? const Color(0xFF00E676)
                              : Colors.white54,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Needle
                    Positioned(
                      left: needleX - 2,
                      child: Container(
                        width: 4,
                        height: 40,
                        decoration: BoxDecoration(
                          color: tuned ? const Color(0xFF00E676) : accent,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  (tuned ? const Color(0xFF00E676) : accent)
                                      .withOpacity(0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('LOW',
                  style: TextStyle(
                      color: Colors.white38, fontWeight: FontWeight.bold)),
              Text('HIGH',
                  style: TextStyle(
                      color: Colors.white38, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

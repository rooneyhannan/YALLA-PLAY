import 'package:flutter/material.dart';
import '../data/tuner_engine.dart';

class TunerScreen extends StatefulWidget {
  const TunerScreen({super.key});

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> {
  final TunerEngine _engine = TunerEngine();

  double? _hz;
  double _rms = 0;
  String _note = '--';
  bool _active = false;

  void _toggle() async {
    if (_active) {
      _engine.stop();
      setState(() {
        _active = false;
        _hz = null;
        _rms = 0;
        _note = '--';
      });
    } else {
      setState(() => _active = true);
      try {
        await _engine.start((result) {
          if (!mounted) return;
          setState(() {
            _hz = result.frequency;
            _rms = result.rms;
            _note = result.note;
          });
        });
      } catch (e) {
        print('[TunerScreen] start error: $e');
        setState(() {
          _active = false;
          _note = 'Error';
        });
      }
    }
  }

  @override
  void dispose() {
    _engine.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hzText = _hz != null ? '${_hz!.toStringAsFixed(1)} Hz' : '-- Hz';
    final bool hasSignal = _rms > 0.01;
    final Color accent =
        hasSignal ? const Color(0xFF00E676) : Colors.white38;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Note name — big
              Text(
                _note,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 120,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
              ),

              const SizedBox(height: 16),

              // Frequency
              Text(
                hzText,
                style: TextStyle(
                  color: accent,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 8),

              // RMS bar — visual proof that audio data is flowing
              SizedBox(
                width: 200,
                height: 6,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (_rms * 10).clamp(0.0, 1.0),
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(accent),
                  ),
                ),
              ),

              const SizedBox(height: 4),

              Text(
                _active
                    ? (hasSignal ? 'Signal detected' : 'Listening...')
                    : 'Tap to start',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 40),

              // Start / Stop button
              GestureDetector(
                onTap: _toggle,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _active
                        ? const Color(0xFF00E676).withOpacity(0.15)
                        : Colors.white.withOpacity(0.08),
                    border: Border.all(
                      color: _active
                          ? const Color(0xFF00E676)
                          : Colors.white38,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    _active ? Icons.stop_rounded : Icons.mic_rounded,
                    color: _active
                        ? const Color(0xFF00E676)
                        : Colors.white54,
                    size: 36,
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

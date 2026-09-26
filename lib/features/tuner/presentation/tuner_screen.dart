import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/app_build.dart';
import '../../../core/theme/app_theme.dart';
import '../data/tuner_engine.dart';
import '../data/tuning.dart';
import 'headstock.dart';

enum _Status { idle, starting, listening }

class TunerScreen extends StatefulWidget {
  final VoidCallback onBack;

  /// False while another tab is shown; the microphone is released then.
  final bool active;
  final TunerEngine Function() engineFactory;
  const TunerScreen({
    super.key,
    required this.onBack,
    this.active = true,
    this.engineFactory = createTunerEngine,
  });
  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> with WidgetsBindingObserver {
  static const _green = Color(0xFF3CD98A);
  static const _background = Color(0xFF1A1A1B);
  // The engine reports about 20 times a second.
  static const _readingsUntilTuned = 10, _silentReadingsUntilClear = 12;

  /// Height the page is laid out for at least; shorter screens scale it.
  static const _minHeight = 680.0;

  late final TunerEngine _engine = widget.engineFactory();
  final _smoother = PitchSmoother();
  final Set<int> _tuned = {};
  _Status _status = _Status.idle;
  TunerError? _error;
  int? _target;
  TuningReading? _reading;
  double _level = 0;
  int _silentReadings = 0, _inTuneReadings = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(TunerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) _stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engine.stop();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _status = _Status.starting;
      _error = null;
    });
    try {
      await _engine.start(_onPitch);
      if (mounted && _status == _Status.starting) {
        setState(() => _status = _Status.listening);
      }
    } on TunerException catch (e) {
      if (mounted) {
        setState(() {
          _status = _Status.idle;
          _error = e.error;
        });
      }
    }
  }

  void _stop() {
    if (_status == _Status.idle) return;
    _engine.stop();
    _smoother.reset();
    if (!mounted) return;
    // Called from didUpdateWidget, where a rebuild is already on its way.
    _status = _Status.idle;
    _reading = null;
    _level = 0;
  }

  void _onPitch(double? frequency, double level) {
    if (!mounted || _status != _Status.listening) return;
    setState(() {
      _level = level;
      if (frequency == null) {
        _inTuneReadings = 0;
        if (++_silentReadings >= _silentReadingsUntilClear) {
          _reading = null;
          _smoother.reset();
        }
        return;
      }
      _silentReadings = 0;
      final heard = readTuning(frequency, target: _target).frequency;
      final reading = readTuning(_smoother.add(heard), target: _target);
      _reading = reading;
      _inTuneReadings = reading.inTune ? _inTuneReadings + 1 : 0;
      if (_inTuneReadings >= _readingsUntilTuned) {
        _tuned.add(reading.stringIndex);
      }
    });
  }

  void _select(int? target) => setState(() {
    _target = target;
    _inTuneReadings = 0;
    _smoother.reset();
    _reading = null;
  });

  String get _hint {
    if (_error != null) {
      return switch (_error!) {
        TunerError.permissionDenied =>
          'لم يُسمح باستخدام الميكروفون. فعّل الإذن من إعدادات المتصفح ثم حاول مجدداً.',
        TunerError.noMicrophone => 'لم يتم العثور على ميكروفون.',
        TunerError.unsupported =>
          'هذا المتصفح لا يدعم الاستماع. افتح التطبيق في Chrome أو Safari.',
        TunerError.failed => 'تعذّر تشغيل الميكروفون. حاول مرة أخرى.',
      };
    }
    if (_status == _Status.idle) {
      return 'اضغط «ابدأ الاستماع» واسمح باستخدام الميكروفون';
    }
    if (_status == _Status.starting) return 'جارٍ تشغيل الميكروفون…';
    final reading = _reading;
    if (reading == null) {
      if (_tuned.length == standardTuning.length) {
        return 'رائع! كل الأوتار مضبوطة';
      }
      return _target == null
          ? 'اعزف على وتر واتركه يرن'
          : 'اعزف على وتر ${standardTuning[_target!].label}';
    }
    if (reading.inTune) return 'الوتر مضبوط';
    return reading.cents < 0
        ? 'منخفض — شُدّ الوتر قليلاً'
        : 'مرتفع — أرخِ الوتر قليلاً';
  }

  @override
  Widget build(BuildContext context) {
    final reading = _reading;
    final shown = reading?.stringIndex ?? _target;
    final inTune = reading?.inTune ?? false;
    final listening = _status == _Status.listening;
    return ColoredBox(
      color: _background,
      child: LayoutBuilder(
        builder: (context, c) {
          // One fixed screen, never scrolled: spare height goes to the
          // headstock photo, and shorter screens scale the whole page down.
          final height = math.max(c.maxHeight, _minHeight);
          final page = SizedBox(
            // Widened by the same factor it is scaled down, so the scaled
            // page still spans the full width.
            width: c.maxWidth * height / c.maxHeight,
            height: height,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton.filled(
                        tooltip: 'العودة للرئيسية',
                        onPressed: widget.onBack,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white10,
                          minimumSize: const Size(48, 48),
                        ),
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const Spacer(),
                      Tooltip(
                        message: 'تلقائي: يتعرف على الوتر الذي تعزفه',
                        child: OutlinedButton.icon(
                          key: const ValueKey('tuner-mode'),
                          onPressed: () => _select(null),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white12),
                            backgroundColor: Colors.white.withValues(
                              alpha: .04,
                            ),
                          ),
                          icon: Icon(
                            Icons.circle,
                            size: 10,
                            color: _target == null ? _green : AppTheme.cream,
                          ),
                          label: Text(
                            _target == null ? 'تلقائي' : 'يدوي',
                            style: TextStyle(
                              color: _target == null ? _green : AppTheme.cream,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    shown == null ? '—' : standardTuning[shown].label,
                    key: const ValueKey('tuner-note'),
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 46,
                      fontWeight: FontWeight.w500,
                      color: shown == null
                          ? Colors.white24
                          : inTune
                          ? _green
                          : AppTheme.gold,
                    ),
                  ),
                  SizedBox(
                    height: 20,
                    child: reading == null
                        ? null
                        : Text(
                            '${reading.frequency.toStringAsFixed(1)} Hz · '
                            '${reading.cents >= 0 ? '+' : ''}'
                            '${reading.cents.round()} cent',
                            key: const ValueKey('tuner-cents'),
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.cream,
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 420,
                    height: 84,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: reading?.cents ?? 0),
                      duration: const Duration(milliseconds: 150),
                      builder: (context, cents, _) => CustomPaint(
                        painter: _MeterPainter(
                          cents: reading == null ? null : cents,
                          color: inTune ? _green : AppTheme.gold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: 160,
                    child: LinearProgressIndicator(
                      value: listening ? (_level * 8).clamp(0, 1) : 0,
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(2),
                      backgroundColor: Colors.white10,
                      color: _green.withValues(alpha: .7),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 44,
                    child: Center(
                      child: Text(
                        _hint,
                        key: const ValueKey('tuner-hint'),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _error != null
                              ? const Color(0xFFFFB4A5)
                              : inTune
                              ? _green
                              : AppTheme.cream,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  listening
                      ? OutlinedButton.icon(
                          key: const ValueKey('tuner-listen'),
                          onPressed: () => setState(_stop),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.cream,
                            side: const BorderSide(color: Colors.white24),
                          ),
                          icon: const Icon(Icons.mic_off_outlined),
                          label: const Text('إيقاف الاستماع'),
                        )
                      : FilledButton.icon(
                          key: const ValueKey('tuner-listen'),
                          onPressed: _status == _Status.starting
                              ? null
                              : _start,
                          icon: const Icon(Icons.mic_rounded),
                          label: const Text('ابدأ الاستماع'),
                        ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: Headstock(
                        background: _background,
                        highlighted: shown,
                        inTune: inTune,
                        pulsing: listening && widget.active,
                        // A copy, so the painter notices newly tuned strings.
                        tuned: {..._tuned},
                        onSelect: _select,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'E · A · D · G · H · E   ·   v$appBuild',
                    key: ValueKey('tuner-footer'),
                    textDirection: TextDirection.ltr,
                    style: TextStyle(color: Colors.white30, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
          return height == c.maxHeight ? page : FittedBox(child: page);
        },
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  /// Needle position; null hides the needle.
  final double? cents;
  final Color color;
  const _MeterPainter({required this.cents, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final reach = cx - 38;
    final p = Paint()
      ..color = const Color(0xFF4B4B4B)
      ..strokeWidth = 2;
    final gap = (size.width - 74) / 14;
    for (var i = 0; i < 6; i++) {
      final x = 38 + i * gap;
      final height = i == 5 ? 40.0 : 20.0;
      canvas.drawLine(Offset(cx - x, 68 - height), Offset(cx - x, 68), p);
      canvas.drawLine(Offset(cx + x, 68 - height), Offset(cx + x, 68), p);
    }
    // The in-tune zone, ±5 cents of the full ±50 cent scale.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, 36),
          width: (reach * inTuneCents / 50 * 2).clamp(48, reach).toDouble(),
          height: 64,
        ),
        const Radius.circular(6),
      ),
      Paint()..color = Colors.white10,
    );
    canvas.drawLine(
      Offset(cx, 4),
      Offset(cx, 68),
      Paint()
        ..color = Colors.white24
        ..strokeWidth = 1,
    );
    if (cents == null) return;
    // LTR on purpose: flat on the left, sharp on the right, as on any tuner.
    final x = cx + (cents!.clamp(-50, 50) / 50) * reach;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, 72),
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(x, 76), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MeterPainter oldDelegate) =>
      oldDelegate.cents != cents || oldDelegate.color != color;
}

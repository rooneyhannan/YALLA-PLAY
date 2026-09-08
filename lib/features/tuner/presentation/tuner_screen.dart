import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/design_widgets.dart';

class TunerScreen extends StatefulWidget {
  final VoidCallback onBack;
  const TunerScreen({super.key, required this.onBack});
  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> {
  int? _string;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF1A1A1B),
    child: LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
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
                        Icons.arrow_forward_ios_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _string = null),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white12),
                        backgroundColor: Colors.white.withValues(alpha: .04),
                      ),
                      icon: Icon(
                        Icons.circle,
                        size: 10,
                        color: _string == null
                            ? const Color(0xFF3CD98A)
                            : AppTheme.cream,
                      ),
                      label: Text(
                        _string == null ? 'تلقائي' : 'يدوي',
                        style: const TextStyle(color: Color(0xFF3CD98A)),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: (c.maxHeight * .13).clamp(28, 100).toDouble()),
                Text(
                  _string == null
                      ? '—'
                      : const ['E', 'H', 'G', 'D', 'A', 'E'][_string!],
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w500,
                    color: _string == null ? Colors.white24 : AppTheme.gold,
                  ),
                ),
                const SizedBox(height: 20),
                const SizedBox(
                  width: 420,
                  height: 84,
                  child: CustomPaint(painter: _MeterPainter()),
                ),
                const SizedBox(height: 16),
                const Text(
                  'معاينة الدوزان — الاستماع غير مفعّل',
                  style: TextStyle(fontSize: 12, color: AppTheme.cream),
                ),
                const SizedBox(height: 36),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Column(
                    children: [
                      _pegs([0, 1, 2], ['E', 'H', 'G']),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: (c.maxWidth * .4).clamp(130, 270).toDouble(),
                        width: double.infinity,
                        child: const DesignImage(
                          's4_0.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _pegs([3, 4, 5], ['D', 'A', 'E']),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'E · A · D · G · H · E',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(color: Colors.white30, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _pegs(List<int> indexes, List<String> labels) => Row(
    textDirection: TextDirection.ltr,
    mainAxisAlignment: MainAxisAlignment.spaceAround,
    children: List.generate(
      3,
      (i) => OutlinedButton(
        key: ValueKey('tuner-string-${indexes[i]}'),
        onPressed: () => setState(() => _string = indexes[i]),
        style: OutlinedButton.styleFrom(
          foregroundColor: _string == indexes[i]
              ? AppTheme.gold
              : AppTheme.text,
          backgroundColor: _string == indexes[i]
              ? AppTheme.gold.withValues(alpha: .08)
              : Colors.transparent,
          side: BorderSide(
            color: _string == indexes[i] ? AppTheme.gold : Colors.white38,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          minimumSize: const Size(56, 48),
        ),
        child: Text(
          labels[i],
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
    ),
  );
}

class _MeterPainter extends CustomPainter {
  const _MeterPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
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
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, 36), width: 48, height: 64),
        const Radius.circular(6),
      ),
      Paint()..color = Colors.white10,
    );
    canvas.drawLine(
      Offset(cx, 4),
      Offset(cx, 68),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

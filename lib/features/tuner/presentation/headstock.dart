import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/tuning.dart';

/// Where everything sits in the headstock drawing, in design units of a
/// [width] × [height] canvas that is scaled to fit. The headstock points
/// left and the neck right, strings 1 (high E) to 6 (low E) top to bottom
/// at the nut, as a guitar looks from the front.
abstract final class HeadstockGeometry {
  static const width = 920.0, height = 560.0;
  static const nutX = 720.0, nutWidth = 16.0, centerY = 281.0;
  static const keySize = Size(130, 96);

  /// String index (0 = high E) → tuning post. The top row holds strings
  /// 3-2-1 left to right, the bottom row 4-5-6.
  static const posts = <Offset>[
    Offset(550, 222),
    Offset(400, 222),
    Offset(250, 222),
    Offset(250, 340),
    Offset(400, 340),
    Offset(550, 340),
  ];

  static double nutY(int string) => 206 + string * 30.0;

  static bool isTop(int string) => string < 3;

  /// The tuner key standing out from the headstock edge beside a post.
  static Rect key(int string) => Rect.fromCenter(
    center: Offset(posts[string].dx, isTop(string) ? 70 : 492),
    width: keySize.width,
    height: keySize.height,
  );

  /// The string from its post over the nut to the end of the drawing.
  static Path stringPath(int string) => Path()
    ..moveTo(posts[string].dx, posts[string].dy)
    ..lineTo(nutX, nutY(string))
    ..lineTo(width, nutY(string));

  static Path outline() => Path()
    ..moveTo(nutX, 188)
    ..lineTo(600, 176)
    ..cubicTo(480, 166, 380, 150, 290, 146)
    ..cubicTo(190, 140, 70, 170, 60, centerY)
    ..cubicTo(70, 392, 190, 422, 290, 416)
    ..cubicTo(380, 412, 480, 396, 600, 386)
    ..lineTo(nutX, 374)
    ..close();

  /// Scale and offset that fit the drawing into [size], centered.
  static (double, Offset) fit(Size size) {
    final scale = math.min(size.width / width, size.height / height);
    return (
      scale,
      Offset(
        (size.width - width * scale) / 2,
        (size.height - height * scale) / 2,
      ),
    );
  }
}

/// A drawn guitar headstock whose tuner keys carry the string names. The
/// string being tuned lights up from its key along the string.
class Headstock extends StatefulWidget {
  /// String to light up, or null.
  final int? highlighted;
  final bool inTune;

  /// Pulse the light, while the microphone is listening.
  final bool pulsing;
  final Set<int> tuned;
  final ValueChanged<int> onSelect;

  /// Page color the end of the neck fades into.
  final Color background;
  const Headstock({
    super.key,
    required this.background,
    required this.highlighted,
    required this.inTune,
    required this.pulsing,
    required this.tuned,
    required this.onSelect,
  });

  @override
  State<Headstock> createState() => _HeadstockState();
}

class _HeadstockState extends State<Headstock> with TickerProviderStateMixin {
  static const _green = Color(0xFF3CD98A);
  late final _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.highlighted != null) _sweep.value = 1;
    _updatePulse();
  }

  @override
  void didUpdateWidget(Headstock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlighted != oldWidget.highlighted) {
      _sweep.forward(from: 0);
    }
    _updatePulse();
  }

  void _updatePulse() {
    if (widget.pulsing && widget.highlighted != null) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final size = c.biggest;
      final (scale, offset) = HeadstockGeometry.fit(size);
      final light = widget.inTune ? _green : AppTheme.gold;
      return Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              label: 'رأس الغيتار مع مفاتيح الأوتار',
              child: CustomPaint(
                key: const ValueKey('tuner-headstock'),
                painter: _HeadstockPainter(
                  background: widget.background,
                  highlighted: widget.highlighted,
                  light: light,
                  tuned: widget.tuned,
                  sweep: _sweep,
                  pulse: _pulse,
                ),
              ),
            ),
          ),
          for (var i = 0; i < standardTuning.length; i++)
            _key(i, scale, offset, light),
        ],
      );
    },
  );

  Widget _key(int i, double scale, Offset offset, Color light) {
    final rect = HeadstockGeometry.key(i);
    final lit = widget.highlighted == i;
    final tuned = widget.tuned.contains(i);
    return Positioned.fromRect(
      rect: Rect.fromLTWH(
        offset.dx + rect.left * scale,
        offset.dy + rect.top * scale,
        rect.width * scale,
        rect.height * scale,
      ),
      child: Semantics(
        button: true,
        selected: lit,
        label: 'وتر ${standardTuning[i].label}${tuned ? '، مضبوط' : ''}',
        excludeSemantics: true,
        child: InkWell(
          key: ValueKey('tuner-string-$i'),
          onTap: () => widget.onSelect(i),
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(36 * scale),
          ),
          child: Center(
            child: FittedBox(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    standardTuning[i].label,
                    style: TextStyle(
                      fontSize: 44 * scale,
                      fontWeight: FontWeight.w700,
                      color: lit ? const Color(0xFF241A00) : Colors.white,
                    ),
                  ),
                  if (tuned) ...[
                    SizedBox(width: 6 * scale),
                    Icon(
                      Icons.check_rounded,
                      key: ValueKey('tuner-tuned-$i'),
                      size: 36 * scale,
                      color: lit ? const Color(0xFF241A00) : _green,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeadstockPainter extends CustomPainter {
  final int? highlighted;
  final Color light;
  final Set<int> tuned;
  final Animation<double> sweep, pulse;
  final Color background;
  _HeadstockPainter({
    required this.background,
    required this.highlighted,
    required this.light,
    required this.tuned,
    required this.sweep,
    required this.pulse,
  }) : super(repaint: Listenable.merge([sweep, pulse]));

  static const _green = Color(0xFF3CD98A);

  @override
  void paint(Canvas canvas, Size size) {
    final (scale, offset) = HeadstockGeometry.fit(size);
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..scale(scale);
    // Strength of the light: fades in with the sweep, then breathes.
    final glow =
        Curves.easeOut.transform(sweep.value) * (.6 + .4 * pulse.value);

    _neck(canvas);
    for (var i = 0; i < 6; i++) {
      _stem(canvas, i);
    }
    _wood(canvas);
    _strings(canvas, glow);
    for (var i = 0; i < 6; i++) {
      _post(canvas, i, glow);
      _keyShape(canvas, i, glow);
    }
    // The neck fades out into the page instead of ending in a hard edge.
    const fade = Rect.fromLTRB(800, 170, HeadstockGeometry.width, 390);
    canvas.drawRect(
      fade,
      Paint()
        ..shader = ui.Gradient.linear(fade.centerLeft, fade.centerRight, [
          background.withValues(alpha: 0),
          background,
        ]),
    );
    canvas.restore();
  }

  void _neck(Canvas canvas) {
    const board = Rect.fromLTRB(
      HeadstockGeometry.nutX,
      190,
      HeadstockGeometry.width,
      372,
    );
    canvas.drawRect(
      board,
      Paint()
        ..shader = ui.Gradient.linear(board.topCenter, board.bottomCenter, [
          const Color(0xFF3B2416),
          const Color(0xFF24150C),
        ]),
    );
    canvas.drawLine(
      const Offset(850, 190),
      const Offset(850, 372),
      Paint()
        ..color = const Color(0xFFD4B26A)
        ..strokeWidth = 5,
    );
    canvas.drawRect(
      const Rect.fromLTWH(
        HeadstockGeometry.nutX,
        186,
        HeadstockGeometry.nutWidth,
        190,
      ),
      Paint()..color = const Color(0xFFF3EFE6),
    );
  }

  void _wood(Canvas canvas) {
    final outline = HeadstockGeometry.outline();
    canvas.drawShadow(outline, Colors.black, 18, false);
    canvas.drawPath(
      outline,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 140),
          const Offset(0, 420),
          [
            const Color(0xFF7A3E1B),
            const Color(0xFFB0692F),
            const Color(0xFF9A5526),
            const Color(0xFF6E3717),
          ],
          [0, .35, .7, 1],
        ),
    );
    // Faint grain following the headstock.
    canvas
      ..save()
      ..clipPath(outline);
    final grain = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0x1F2B1206);
    for (var y = 150.0; y < 420; y += 17) {
      final bend = (y - HeadstockGeometry.centerY) * .08;
      canvas.drawPath(
        Path()
          ..moveTo(40, y + bend)
          ..cubicTo(300, y - 6, 500, y + 8 - bend, 760, y - bend),
        grain,
      );
    }
    canvas.restore();
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF4E250F),
    );
  }

  void _strings(Canvas canvas, double glow) {
    for (var i = 0; i < 6; i++) {
      final wound = i >= 3;
      canvas.drawPath(
        HeadstockGeometry.stringPath(i),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 + i * .5
          ..color = wound ? const Color(0xFFC9A36A) : const Color(0xFFD6D6D6),
      );
    }
    final lit = highlighted;
    if (lit == null || glow == 0) return;
    // The light runs from the key along the string to the end.
    final metric = HeadstockGeometry.stringPath(lit).computeMetrics().first;
    final part = metric.extractPath(
      0,
      metric.length * Curves.easeOutCubic.transform(sweep.value),
    );
    canvas
      ..drawPath(
        part,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16
          ..strokeCap = StrokeCap.round
          ..color = light.withValues(alpha: .55 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      )
      ..drawPath(
        part,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = Color.lerp(light, Colors.white, .55)!,
      );
  }

  void _stem(Canvas canvas, int i) {
    final key = HeadstockGeometry.key(i);
    final top = HeadstockGeometry.isTop(i);
    final stem = Rect.fromLTRB(
      key.center.dx - 16,
      top ? key.bottom - 4 : HeadstockGeometry.posts[i].dy + 20,
      key.center.dx + 16,
      top ? HeadstockGeometry.posts[i].dy - 20 : key.top + 4,
    );
    final lit = highlighted == i;
    canvas.drawRRect(
      RRect.fromRectAndRadius(stem, const Radius.circular(6)),
      Paint()..color = lit ? light : const Color(0xFF1E1E1E),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(stem, const Radius.circular(6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = lit ? light : Colors.white70,
    );
  }

  void _post(Canvas canvas, int i, double glow) {
    final center = HeadstockGeometry.posts[i];
    if (highlighted == i && glow > 0) {
      canvas.drawCircle(
        center,
        44,
        Paint()
          ..color = light.withValues(alpha: .5 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );
    }
    canvas
      ..drawCircle(
        center + const Offset(3, 5),
        28,
        Paint()..color = const Color(0x66000000),
      )
      ..drawCircle(
        center,
        28,
        Paint()
          ..shader = ui.Gradient.radial(
            center - const Offset(8, 8),
            34,
            [Colors.white, const Color(0xFFA7A7A7), const Color(0xFF555555)],
            [0, .55, 1],
          ),
      )
      ..drawCircle(center, 10, Paint()..color = const Color(0xFF6B6B6B));
  }

  void _keyShape(Canvas canvas, int i, double glow) {
    final shape = RRect.fromRectAndRadius(
      HeadstockGeometry.key(i),
      const Radius.circular(36),
    );
    final lit = highlighted == i;
    if (lit && glow > 0) {
      canvas.drawRRect(
        shape.inflate(6),
        Paint()
          ..color = light.withValues(alpha: .7 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
      );
    }
    canvas
      ..drawRRect(shape, Paint()..color = lit ? light : const Color(0xFF1E1E1E))
      ..drawRRect(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = lit
              ? Color.lerp(light, Colors.white, .5)!
              : tuned.contains(i)
              ? _green
              : Colors.white70,
      );
  }

  @override
  bool shouldRepaint(_HeadstockPainter old) =>
      old.highlighted != highlighted ||
      old.light != light ||
      !setEquals(old.tuned, tuned);
}

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/tuning.dart';

/// Where everything sits in the headstock drawing, in design units of a
/// [width] × [height] canvas that is scaled to fit. Proportions follow a
/// classic acoustic headstock seen from the front: it points left, widens
/// towards its rounded end, and meets the neck at the nut on the right,
/// with strings 1 (high E) to 6 (low E) top to bottom.
abstract final class HeadstockGeometry {
  static const width = 910.0, height = 516.0;
  static const nutX = 665.0, nutWidth = 15.0, centerY = 252.0;
  static const neckTop = 145.0, neckBottom = 362.0;

  /// Where the lit string ends and its name is written.
  static const stringEnd = 862.0, labelX = 888.0;
  static const keySize = Size(112, 64);

  /// String index (0 = high E) → tuning post. The top row holds strings
  /// 3-2-1 left to right, the bottom row 4-5-6.
  static const posts = <Offset>[
    Offset(495, 158),
    Offset(348, 158),
    Offset(202, 158),
    Offset(202, 345),
    Offset(348, 345),
    Offset(495, 345),
  ];

  static double nutY(int string) => 165 + string * 35.0;

  static bool isTop(int string) => string < 3;

  /// The tuner button standing out from the headstock edge beside a post.
  static Rect key(int string) => Rect.fromCenter(
    center: Offset(posts[string].dx, isTop(string) ? 48 : 468),
    width: keySize.width,
    height: keySize.height,
  );

  /// The string from its post over the nut along the fretboard.
  static Path stringPath(int string, {double end = width}) => Path()
    ..moveTo(posts[string].dx, posts[string].dy)
    ..lineTo(nutX, nutY(string))
    ..lineTo(end, nutY(string));

  static Path outline() => Path()
    ..moveTo(nutX, neckTop)
    // Shoulder where the neck widens into the headstock.
    ..lineTo(540, 110)
    ..cubicTo(400, 100, 220, 88, 90, 85)
    // The rounded end, wider than the neck.
    ..cubicTo(40, 118, 12, 190, 12, centerY)
    ..cubicTo(12, 314, 40, 386, 90, 419)
    ..cubicTo(220, 416, 400, 405, 540, 394)
    ..lineTo(nutX, neckBottom)
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
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: ValueKey('tuner-string-$i'),
            onTap: () => widget.onSelect(i),
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24 * scale),
            ),
            child: Center(
              child: FittedBox(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      standardTuning[i].label,
                      style: TextStyle(
                        fontSize: 38 * scale,
                        fontWeight: FontWeight.w700,
                        color: lit ? const Color(0xFF241A00) : Colors.white,
                      ),
                    ),
                    if (tuned) ...[
                      SizedBox(width: 6 * scale),
                      Icon(
                        Icons.check_rounded,
                        key: ValueKey('tuner-tuned-$i'),
                        size: 30 * scale,
                        color: lit ? const Color(0xFF241A00) : _green,
                      ),
                    ],
                  ],
                ),
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
      _shaft(canvas, i);
    }
    _wood(canvas);
    _strings(canvas);
    _fade(canvas);
    _light(canvas, glow);
    for (var i = 0; i < 6; i++) {
      _post(canvas, i, glow);
      _button(canvas, i, glow);
    }
    canvas.restore();
  }

  void _neck(Canvas canvas) {
    const board = Rect.fromLTRB(
      HeadstockGeometry.nutX,
      HeadstockGeometry.neckTop,
      HeadstockGeometry.width,
      HeadstockGeometry.neckBottom,
    );
    canvas.drawRect(
      board,
      Paint()
        ..shader = ui.Gradient.linear(
          board.topCenter,
          board.bottomCenter,
          [
            const Color(0xFF3A2317),
            const Color(0xFF2B190F),
            const Color(0xFF3A2317),
          ],
          [0, .5, 1],
        ),
    );
    canvas
      ..drawLine(
        const Offset(790, HeadstockGeometry.neckTop),
        const Offset(790, HeadstockGeometry.neckBottom),
        Paint()
          ..color = const Color(0xFFD8B46A)
          ..strokeWidth = 4,
      )
      ..drawRect(
        const Rect.fromLTWH(
          HeadstockGeometry.nutX,
          HeadstockGeometry.neckTop - 4,
          HeadstockGeometry.nutWidth,
          HeadstockGeometry.neckBottom - HeadstockGeometry.neckTop + 8,
        ),
        Paint()..color = const Color(0xFFF2EEE4),
      );
  }

  void _wood(Canvas canvas) {
    final outline = HeadstockGeometry.outline();
    canvas.drawShadow(outline, Colors.black, 22, false);
    canvas.drawPath(
      outline,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 85),
          const Offset(0, 420),
          const [
            Color(0xFF6B3413),
            Color(0xFF9E5724),
            Color(0xFFB0662D),
            Color(0xFF8E4A1E),
            Color(0xFF5C2B10),
          ],
          [0, .22, .5, .8, 1],
        ),
    );
    canvas
      ..save()
      ..clipPath(outline);
    // Straight, fine grain along the length of the headstock.
    final grain = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final random = math.Random(7);
    for (var y = 88.0; y < 420; y += 7 + random.nextDouble() * 9) {
      grain.color = Color.fromRGBO(40, 16, 4, .08 + random.nextDouble() * .1);
      final wave = random.nextDouble() * 4 - 2;
      canvas.drawPath(
        Path()
          ..moveTo(0, y)
          ..cubicTo(220, y + wave, 440, y - wave, 700, y + wave * .5),
        grain,
      );
    }
    // Darker towards the rounded end, as the wood turns away from the light.
    canvas.drawRect(
      const Rect.fromLTRB(0, 80, 360, 430),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          const Offset(360, 0),
          [const Color(0x66000000), const Color(0x00000000)],
        ),
    );
    _logo(canvas);
    canvas.restore();
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = const Color(0xFF3F1D0A),
    );
  }

  /// "يلا" pressed into the wood near the end of the headstock.
  void _logo(Canvas canvas) {
    TextPainter text(Color color) => TextPainter(
      text: TextSpan(
        text: 'يلا',
        style: TextStyle(
          fontFamily: 'IBM Plex Sans Arabic',
          fontSize: 58,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
      textDirection: TextDirection.rtl,
    )..layout();
    final dark = text(const Color(0x5C2A0F02));
    final at = Offset(
      100 - dark.width / 2,
      HeadstockGeometry.centerY - dark.height / 2,
    );
    text(const Color(0x1FFFE2C0)).paint(canvas, at + const Offset(0, 2));
    dark.paint(canvas, at);
  }

  void _strings(Canvas canvas) {
    for (var i = 0; i < 6; i++) {
      final wound = i >= 3;
      canvas.drawPath(
        HeadstockGeometry.stringPath(i),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 + i * .45
          ..color = wound ? const Color(0xFFC8A46E) : const Color(0xFFD9D9D9),
      );
    }
  }

  /// The neck fades out into the page instead of ending in a hard edge.
  void _fade(Canvas canvas) {
    const fade = Rect.fromLTRB(760, 120, HeadstockGeometry.width, 390);
    canvas.drawRect(
      fade,
      Paint()
        ..shader = ui.Gradient.linear(
          fade.centerLeft,
          Offset(870, fade.center.dy),
          [background.withValues(alpha: 0), background],
        ),
    );
  }

  /// The lit string, running from its post to the end with its name.
  void _light(Canvas canvas, double glow) {
    final lit = highlighted;
    if (lit == null || glow == 0) return;
    final metric = HeadstockGeometry.stringPath(
      lit,
      end: HeadstockGeometry.stringEnd,
    ).computeMetrics().first;
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
          ..color = Color.lerp(light, Colors.white, .6)!,
      );
    final label = TextPainter(
      text: TextSpan(
        text: standardTuning[lit].label,
        style: TextStyle(
          fontFamily: 'IBM Plex Sans Arabic',
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: Color.lerp(
            light,
            Colors.white,
            .6,
          )!.withValues(alpha: sweep.value),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(
      canvas,
      Offset(
        HeadstockGeometry.labelX - label.width / 2,
        HeadstockGeometry.nutY(lit) - label.height / 2,
      ),
    );
  }

  /// The metal shaft from a tuner button into the headstock.
  void _shaft(Canvas canvas, int i) {
    final key = HeadstockGeometry.key(i);
    final top = HeadstockGeometry.isTop(i);
    final shaft = Rect.fromLTRB(
      key.center.dx - 9,
      top ? key.bottom - 2 : HeadstockGeometry.posts[i].dy,
      key.center.dx + 9,
      top ? HeadstockGeometry.posts[i].dy : key.top + 2,
    );
    final lit = highlighted == i;
    canvas
      ..drawRect(shaft, Paint()..color = lit ? light : const Color(0xFF1C1C1E))
      ..drawRect(
        shaft,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = lit ? light : Colors.white70,
      );
  }

  void _post(Canvas canvas, int i, double glow) {
    final center = HeadstockGeometry.posts[i];
    if (highlighted == i && glow > 0) {
      canvas.drawCircle(
        center,
        46,
        Paint()
          ..color = light.withValues(alpha: .5 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );
    }
    canvas
      ..drawCircle(
        center + const Offset(4, 7),
        31,
        Paint()
          ..color = const Color(0x80000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      )
      // Chrome washer.
      ..drawCircle(
        center,
        30,
        Paint()
          ..shader = ui.Gradient.radial(
            center - const Offset(10, 12),
            40,
            const [Colors.white, Color(0xFFC4C4C4), Color(0xFF6A6A6A)],
            [0, .45, 1],
          ),
      )
      ..drawCircle(
        center,
        30,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF4A4A4A),
      )
      // String post.
      ..drawCircle(
        center,
        12,
        Paint()
          ..shader = ui.Gradient.radial(center - const Offset(4, 4), 14, const [
            Color(0xFFF2F2F2),
            Color(0xFF8A8A8A),
          ]),
      )
      ..drawCircle(center, 3.5, Paint()..color = const Color(0xFF5A5A5A));
  }

  /// A tuner button: domed on the outside, flat where its shaft enters.
  void _button(Canvas canvas, int i, double glow) {
    final rect = HeadstockGeometry.key(i);
    const round = Radius.circular(30), flat = Radius.circular(14);
    final top = HeadstockGeometry.isTop(i);
    final shape = RRect.fromRectAndCorners(
      rect,
      topLeft: top ? round : flat,
      topRight: top ? round : flat,
      bottomLeft: top ? flat : round,
      bottomRight: top ? flat : round,
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
      ..drawRRect(shape, Paint()..color = lit ? light : const Color(0xFF1C1C1E))
      ..drawRRect(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
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
      old.background != background ||
      !setEquals(old.tuned, tuned);
}

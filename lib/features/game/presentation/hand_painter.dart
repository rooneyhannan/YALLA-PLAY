import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// One color per finger of the fretting hand, 0 = open string, 1 = index
/// … 4 = pinky. Green, yellow and red are left for the verdicts.
const fingerColors = <Color>[
  Color(0xFF9AA0A6),
  Color(0xFF4F8BFF),
  Color(0xFF3ED8E8),
  Color(0xFFA27BFF),
  Color(0xFFE860C0),
];

const fingerNames = ['وتر مفتوح', 'السبابة', 'الوسطى', 'البنصر', 'الخنصر'];

/// A left hand, palm towards the player, drawn white and see-through; the
/// finger to play lights up in its color.
class HandPainter extends CustomPainter {
  /// 1–4 lights that finger; 0 (open string) lights none.
  final int finger;

  /// How strongly the finger glows, 0 to 1: rises as its note comes near.
  /// Kept in a few steps, so the hand repaints rarely.
  final double glow;
  const HandPainter({required this.finger, required this.glow});

  /// The drawing's own coordinates; it is scaled to fit.
  static const _view = Rect.fromLTWH(70, 240, 400, 650);

  static const _outline = <Offset>[
    Offset(252, 910), Offset(249, 850), Offset(240, 800), Offset(214, 750), //
    Offset(178.9, 679.6), Offset(158.3, 641.7), Offset(139.7, 602.8),
    Offset(123, 562.9), Offset(112.9, 536.6), Offset(108.3, 511.6),
    Offset(115.2, 496.7), Offset(131.3, 499.9), Offset(146.5, 519.4),
    Offset(157.9, 545.1), Offset(176.6, 584), Offset(197.1, 621.9),
    Offset(210, 616), Offset(214, 592), Offset(211, 548), Offset(213, 490),
    Offset(218, 420), Offset(222, 350), Offset(226, 308), Offset(240, 294),
    Offset(255, 302), Offset(260, 326), Offset(262, 390), Offset(265, 450),
    Offset(268, 490), Offset(274, 506), Offset(279, 494), Offset(279, 440),
    Offset(280, 370), Offset(281, 305), Offset(286, 276), Offset(301, 266),
    Offset(316, 276), Offset(322, 304), Offset(323, 370), Offset(323, 440),
    Offset(324, 488), Offset(329, 501), Offset(334, 490), Offset(336, 440),
    Offset(340, 380), Offset(344, 322), Offset(350, 296), Offset(364, 288),
    Offset(377, 298), Offset(381, 322), Offset(380, 380), Offset(377, 440),
    Offset(375, 492), Offset(379, 512), Offset(385, 502), Offset(390, 460),
    Offset(396, 412), Offset(402, 380), Offset(413, 366), Offset(425, 372),
    Offset(430, 392), Offset(428, 440), Offset(423, 490), Offset(418, 530),
    Offset(416, 574), Offset(408, 626), Offset(397, 682), Offset(386, 744),
    Offset(377, 820), Offset(370, 910),
  ];

  /// Index to pinky: base at the webs, tip, and width.
  static const _fingers = [
    (base: Offset(240, 515), tip: Offset(240, 302), width: 44.0),
    (base: Offset(301, 505), tip: Offset(301, 274), width: 44.0),
    (base: Offset(357, 510), tip: Offset(362, 296), width: 40.0),
    (base: Offset(404, 525), tip: Offset(415, 374), width: 34.0),
  ];

  static final Path _hand = _spline(_outline);

  /// Closed Catmull-Rom spline through [points].
  static Path _spline(List<Offset> points) {
    final n = points.length;
    Offset at(int i) => points[(i + n) % n];
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 0; i < n; i++) {
      final p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2);
      final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / _view.width,
      size.height / _view.height,
    );
    canvas
      ..save()
      ..translate(
        (size.width - _view.width * scale) / 2,
        (size.height - _view.height * scale) / 2,
      )
      ..scale(scale)
      ..translate(-_view.left, -_view.top);
    // Everything goes on one layer, so the wrist can fade out at the end.
    canvas.saveLayer(_view.inflate(40), Paint());
    _body(canvas);
    if (finger > 0) _lit(canvas, finger - 1);
    _details(canvas);
    canvas
      ..drawPath(
        _hand,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / math.min(1, scale)
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white.withValues(alpha: .9),
      )
      ..drawRect(
        _view.inflate(40),
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = ui.Gradient.linear(
            const Offset(0, 790),
            const Offset(0, 890),
            [Colors.white, Colors.transparent],
          ),
      )
      ..restore()
      ..restore();
  }

  void _body(Canvas canvas) {
    canvas
      ..drawPath(
        _hand,
        Paint()
          ..color = const Color(0xFFCFE0FF).withValues(alpha: .22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      )
      ..drawPath(
        _hand,
        Paint()
          ..shader =
              ui.Gradient.linear(const Offset(0, 250), const Offset(0, 900), [
                Colors.white.withValues(alpha: .5),
                const Color(0xFFE3ECFF).withValues(alpha: .5),
              ]),
      );
  }

  /// The finger to play, in its color, exactly in the hand's outline.
  void _lit(Canvas canvas, int i) {
    final f = _fingers[i];
    final color = fingerColors[i + 1];
    final strength = .35 + .65 * glow;
    final along = f.tip - f.base;
    final unit = along / along.distance;
    final from = f.base + unit * 10, to = f.tip - unit * 30;
    canvas
      ..drawLine(
        from,
        to,
        Paint()
          ..color = color.withValues(alpha: .7 * strength)
          ..strokeWidth = f.width * 1.3
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      )
      ..save()
      ..clipPath(_hand)
      ..drawLine(
        from,
        f.tip + unit * 20,
        Paint()
          ..color = color.withValues(alpha: .85 * strength)
          ..strokeWidth = f.width * 1.2
          ..strokeCap = StrokeCap.round,
      )
      ..restore();
  }

  void _details(Canvas canvas) {
    void pad(Offset c, double rx, double ry, double alpha, [double deg = 0]) {
      canvas
        ..save()
        ..translate(c.dx, c.dy)
        ..rotate(deg * math.pi / 180)
        ..scale(1, ry / rx)
        ..drawCircle(
          Offset.zero,
          rx,
          Paint()
            ..shader = ui.Gradient.radial(Offset.zero, rx, [
              Colors.white.withValues(alpha: .55 * alpha),
              Colors.white.withValues(alpha: 0),
            ]),
        )
        ..restore();
    }

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    void stroke(Path path, double alpha, [double width = 1.5]) =>
        canvas.drawPath(
          path,
          line
            ..strokeWidth = width
            ..color = Colors.white.withValues(alpha: alpha),
        );

    pad(const Offset(258, 736), 40, 70, .55, -12);
    pad(const Offset(370, 680), 20, 72, .45, -6);
    pad(const Offset(320, 555), 100, 26, .4);
    pad(const Offset(136, 536), 13, 22, .6, -24);
    for (final f in _fingers) {
      Offset at(double t) => f.base + (f.tip - f.base) * t;
      pad(at(.86), f.width * .32, f.width * .5, .6);
      pad(at(.57), f.width * .3, f.width * .4, .25);
      pad(at(.22), f.width * .32, f.width * .55, .25);
      // Creases across the finger: doubled at the base and middle joint.
      final along = f.tip - f.base, unit = along / along.distance;
      final normal = Offset(unit.dy, -unit.dx);
      for (final (t, pair) in [(.03, true), (.42, true), (.71, false)]) {
        final w = f.width * (1 - .2 * t) * .36;
        for (final o in pair ? [0.0, 5.0] : [0.0]) {
          final c = at(t) - unit * o;
          final a = c + normal * w, b = c - normal * w;
          final bow = c - unit * 3 + const Offset(0, 3);
          stroke(
            Path()
              ..moveTo(a.dx, a.dy)
              ..quadraticBezierTo(bow.dx, bow.dy, b.dx, b.dy),
            .42,
            1.3,
          );
        }
      }
    }
    stroke(
      Path()
        ..moveTo(147, 593)
        ..quadraticBezierTo(160, 597, 173, 581),
      .42,
      1.3,
    );
    stroke(
      Path()
        ..moveTo(149, 598)
        ..quadraticBezierTo(162, 602, 175, 586),
      .3,
      1.2,
    );
    // Palm lines: heart, head, life and fate.
    stroke(
      Path()
        ..moveTo(407, 596)
        ..cubicTo(386, 584, 340, 566, 272, 540),
      .55,
    );
    stroke(
      Path()
        ..moveTo(210, 614)
        ..cubicTo(262, 628, 322, 646, 382, 676),
      .5,
    );
    stroke(
      Path()
        ..moveTo(212, 616)
        ..cubicTo(262, 660, 282, 740, 286, 850),
      .55,
    );
    stroke(
      Path()
        ..moveTo(326, 860)
        ..cubicTo(328, 790, 334, 720, 344, 650),
      .2,
    );
  }

  @override
  bool shouldRepaint(HandPainter old) =>
      old.finger != finger || old.glow != glow;
}

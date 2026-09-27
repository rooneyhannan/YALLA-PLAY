import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/ball_path.dart';
import '../data/note_judge.dart';
import '../data/song_data.dart';
import 'hand_painter.dart';

/// A note placed on the song's time line, in ticks.
class GameNote {
  final Note note;
  final double absoluteTime;

  /// Finger of the fretting hand: 1 index … 4 pinky, 0 open string.
  final int finger;
  const GameNote(this.note, this.absoluteTime, {this.finger = 0});
}

/// A verdict shown briefly above the note it was given for.
class FeedbackMark {
  final Verdict verdict;
  final int string;

  /// Screen clock ([HighwayPainter.seconds]) when it was given.
  final double shownAt;
  const FeedbackMark(this.verdict, this.string, this.shownAt);
}

/// Colors a note takes once judged: played on time, played early or late,
/// and not played at all.
const perfectColor = Color(0xFF35E26B),
    offTimeColor = Color(0xFFC6E83A),
    missedColor = Color(0xFFFF4D4D);

Color verdictColor(Verdict verdict) => switch (verdict) {
  Verdict.perfect => perfectColor,
  Verdict.early || Verdict.late => offTimeColor,
  Verdict.missed => missedColor,
};

/// Perspective of the board: a plane seen from above and in front, so it
/// runs away from the viewer. Positions on it are `u`, pixels along time
/// measured at the front edge from the screen center, and `v`, depth from
/// 0 at the front edge to 1 at the back edge.
class BoardProjection {
  final double centerX, frontY, backY;

  /// How much smaller the back edge looks than the front edge.
  static const recede = .3;
  const BoardProjection(this.centerX, this.frontY, this.backY);

  double scale(double v) => 1 / (1 + recede * v);

  double y(double v) =>
      frontY - (frontY - backY) * (1 - scale(v)) / (1 - scale(1));

  /// [lift] raises a point above the board, shrinking with depth.
  Offset project(double u, double v, {double lift = 0}) =>
      Offset(centerX + u * scale(v), y(v) - lift * scale(v));

  /// Depth of a string's lane; the thin strings lie at the back.
  static double stringDepth(double string) => (5.5 - string) / 6;
}

class HighwayPainter extends CustomPainter {
  final List<GameNote> notes;
  final BallPath ball;
  final double currentTick, leadTicks, totalTicks;

  /// Seconds since the screen opened, for the drifting gold dust.
  final double seconds;
  final Color background;

  /// Verdict per note while the microphone scores, else null.
  final List<Verdict?>? verdicts;
  final List<FeedbackMark> feedback;

  /// The note the practice mode waits at, which pulses.
  final int? waiting;
  HighwayPainter({
    this.verdicts,
    this.waiting,
    this.feedback = const [],
    required this.notes,
    required this.ball,
    required this.currentTick,
    required this.leadTicks,
    required this.totalTicks,
    required this.seconds,
    required this.background,
    this.beatTicks = 4,
    this.barTicks = 16,
  });

  /// Ticks of a beat and of a bar, for the lines across the board.
  final double beatTicks, barTicks;

  late double _zoom, _hitU;

  /// Shrinks the ball's jumps on a short board, so they stay on screen.
  late double _lift;
  late BoardProjection _board;

  /// Ball and note time t (in ticks) → position along the board.
  double _u(double t) => _hitU + (t - currentTick) * _zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final narrow = size.width < 600;
    // Narrow screens pack the notes closer, to see about two seconds ahead.
    _zoom = size.width < 450
        ? 26
        : narrow
        ? 34
        : 52;
    _lift = math.min(1.0, size.height / 520);
    final hitX = narrow ? size.width * .24 : size.width * .2;
    _hitU = hitX - size.width / 2;
    _board = BoardProjection(
      size.width / 2,
      size.height * .9,
      size.height * .42,
    );

    _sky(canvas, size);
    _floor(canvas, size);
    _strings(canvas, size);
    _hitLine(canvas);
    _notes(canvas, size);
    _trail(canvas, size);
    _ball(canvas);
    _feedback(canvas);
  }

  void _sky(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
          const Color(0xFF1B1A14),
          background,
        ]),
    );
    // Gold dust drifting slowly upwards.
    final random = math.Random(3);
    final dust = Paint();
    for (var i = 0; i < 46; i++) {
      final speed = 6 + random.nextDouble() * 10;
      final x = random.nextDouble() * size.width;
      final y =
          (random.nextDouble() * size.height * .55 - seconds * speed) %
          (size.height * .55);
      final twinkle = .5 + .5 * math.sin(seconds * 1.7 + i);
      dust.color = AppTheme.gold.withValues(
        alpha: (.08 + .22 * twinkle) * (y / (size.height * .55)),
      );
      canvas.drawCircle(
        Offset(x + math.sin(seconds * .6 + i) * 6, y),
        1 + random.nextDouble() * 2,
        dust,
      );
    }
  }

  void _floor(Canvas canvas, Size size) {
    // Wide enough that the receding back edge still spans the screen.
    final half = size.width / 2 / _board.scale(1) + 40;
    final frontLeft = _board.project(-half, 0);
    final frontRight = _board.project(half, 0);
    final backLeft = _board.project(-half, 1);
    final backRight = _board.project(half, 1);
    final top = Path()
      ..moveTo(frontLeft.dx, frontLeft.dy)
      ..lineTo(frontRight.dx, frontRight.dy)
      ..lineTo(backRight.dx, backRight.dy)
      ..lineTo(backLeft.dx, backLeft.dy)
      ..close();
    // The board's thickness under its front edge.
    canvas.drawRect(
      Rect.fromLTRB(0, frontLeft.dy, size.width, frontLeft.dy + 16),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, frontLeft.dy),
          Offset(0, frontLeft.dy + 16),
          [const Color(0xFF2A2A26), const Color(0xFF121212)],
        ),
    );
    canvas.drawPath(
      top,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, backLeft.dy),
          Offset(0, frontLeft.dy),
          [const Color(0xFF161817), const Color(0xFF262A29)],
        ),
    );
    // Back edge glow where the board meets the sky.
    canvas.drawLine(
      backLeft,
      backRight,
      Paint()
        ..color = AppTheme.gold.withValues(alpha: .25)
        ..strokeWidth = 1.2,
    );
    // Beat lines run from front to back and lean with the perspective.
    final firstBeat =
        ((currentTick - _hitU / _zoom - size.width / _zoom) / beatTicks)
            .floor() *
        beatTicks;
    final tile = Paint()..color = Colors.white.withValues(alpha: .025);
    for (
      var t = firstBeat.toDouble();
      _u(t) * _board.scale(1) < size.width;
      t += beatTicks
    ) {
      if (((t - leadTicks) / beatTicks).round().isEven) {
        final next = t + beatTicks;
        canvas.drawPath(
          Path()
            ..moveTo(_board.project(_u(t), 0).dx, _board.project(_u(t), 0).dy)
            ..lineTo(
              _board.project(_u(next), 0).dx,
              _board.project(_u(next), 0).dy,
            )
            ..lineTo(
              _board.project(_u(next), 1).dx,
              _board.project(_u(next), 1).dy,
            )
            ..lineTo(_board.project(_u(t), 1).dx, _board.project(_u(t), 1).dy)
            ..close(),
          tile,
        );
      }
      final bar = (t - leadTicks) % barTicks == 0;
      canvas.drawLine(
        _board.project(_u(t), 0),
        _board.project(_u(t), 1),
        Paint()
          ..color = AppTheme.gold.withValues(alpha: bar ? .45 : .12)
          ..strokeWidth = bar ? 1.6 : 1,
      );
    }
  }

  void _strings(Canvas canvas, Size size) {
    final half = size.width / 2 / _board.scale(1) + 40;
    for (var i = 0; i < 6; i++) {
      final v = BoardProjection.stringDepth(i.toDouble());
      final left = _board.project(-half, v), right = _board.project(half, v);
      final width = (1.2 + i * .55) * _board.scale(v) * 1.6;
      final wound = i >= 3;
      canvas.drawLine(
        left + const Offset(0, 2),
        right + const Offset(0, 2),
        Paint()
          ..color = Colors.black54
          ..strokeWidth = width,
      );
      canvas.drawLine(
        left,
        right,
        Paint()
          ..color = wound ? const Color(0xFFB8925A) : const Color(0xFFD8D8D8)
          ..strokeWidth = width,
      );
      if (wound) {
        // The winding of the thick strings.
        final wind = Paint()
          ..color = const Color(0xFF6E5330)
          ..strokeWidth = 1;
        for (var x = left.dx % 4; x < right.dx; x += 4) {
          canvas.drawLine(
            Offset(x, left.dy - width / 2),
            Offset(x + 1.5, left.dy + width / 2),
            wind,
          );
        }
      }
    }
  }

  void _hitLine(Canvas canvas) {
    final front = _board.project(_hitU, 0), back = _board.project(_hitU, 1);
    canvas
      ..drawLine(
        front,
        back,
        Paint()
          ..color = AppTheme.gold.withValues(alpha: .35)
          ..strokeWidth = 10
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      )
      ..drawLine(
        front,
        back,
        Paint()
          ..color = AppTheme.gold.withValues(alpha: .8)
          ..strokeWidth = 2,
      );
  }

  void _notes(Canvas canvas, Size size) {
    // Back strings first, so nearer notes overlap them.
    for (var string = 0; string < 6; string++) {
      for (var i = 0; i < notes.length; i++) {
        if (notes[i].note.s - 1 != string) continue;
        _note(canvas, size, notes[i], string, verdicts?[i], i == waiting);
      }
    }
  }

  void _note(
    Canvas canvas,
    Size size,
    GameNote gameNote,
    int string,
    Verdict? verdict,
    bool waiting,
  ) {
    final start = gameNote.absoluteTime + leadTicks;
    final u0 = _u(start);
    final u1 = _u(start + gameNote.note.d) - 6;
    final v = BoardProjection.stringDepth(string.toDouble());
    final scale = _board.scale(v);
    final a = _board.project(u0, v), b = _board.project(u1, v);
    if (b.dx < -40 || a.dx > size.width + 40) return;
    final height = 36 * scale;
    final hit = verdict != null && verdict != Verdict.missed;
    // Judged notes take the color of their verdict; hit ones keep shining
    // after they pass.
    final color = verdict == null
        ? fingerColors[gameNote.finger]
        : verdictColor(verdict);
    final past = u1 < _hitU;
    final playing =
        hit || waiting || (u0 <= _hitU && _hitU <= u1 + 6 && verdicts == null);
    final alpha = verdict == Verdict.missed
        ? .7
        : past && !hit
        ? .3
        : 1.0;
    final pill = RRect.fromLTRBR(
      a.dx,
      a.dy - height / 2,
      math.max(b.dx, a.dx + height),
      a.dy + height / 2,
      Radius.circular(height / 2),
    );
    // Shadow on the board below the note.
    canvas.drawRRect(
      pill.shift(Offset(0, 5 * scale)),
      Paint()
        ..color = Colors.black.withValues(alpha: .45 * alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * scale),
    );
    if (playing) {
      final glow = waiting ? .35 + .35 * math.sin(seconds * 7) : .6;
      canvas.drawRRect(
        pill.inflate((waiting ? 7 : 4) * scale),
        Paint()
          ..color = (waiting ? Colors.white : color).withValues(alpha: glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 * scale),
      );
    }
    // Rounded body: light on top, darker towards its lower edge.
    canvas.drawRRect(
      pill,
      Paint()
        ..shader = ui.Gradient.linear(
          pill.outerRect.topCenter,
          pill.outerRect.bottomCenter,
          [
            Color.lerp(
              color,
              Colors.white,
              playing ? .45 : .25,
            )!.withValues(alpha: alpha),
            color.withValues(alpha: alpha),
            Color.lerp(color, Colors.black, .35)!.withValues(alpha: alpha),
          ],
          [0, .45, 1],
        ),
    );
    if (verdict == Verdict.perfect) {
      _check(canvas, a + Offset(height / 2, 0), height * .26);
      return;
    }
    final label = TextPainter(
      text: TextSpan(
        text: '${gameNote.note.f}',
        style: TextStyle(
          color: Colors.white.withValues(alpha: past ? .5 : 1),
          fontSize: 21 * scale,
          fontWeight: FontWeight.w700,
          fontFamily: 'IBM Plex Sans Arabic',
          shadows: const [Shadow(blurRadius: 3, color: Colors.black45)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(
      canvas,
      Offset(a.dx + height / 2 - label.width / 2, a.dy - label.height / 2),
    );
  }

  /// A check mark centered on [center], for a note played right.
  void _check(Canvas canvas, Offset center, double size) {
    final path = Path()
      ..moveTo(center.dx - size, center.dy)
      ..lineTo(center.dx - size * .3, center.dy + size * .7)
      ..lineTo(center.dx + size, center.dy - size * .7);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * .45
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  Offset _ballPoint(double t) {
    final state = ball.at(t);
    return _board.project(
      _u(t),
      BoardProjection.stringDepth(state.string),
      lift: state.height * _lift + 14,
    );
  }

  /// Dotted flight path: where the ball came from and where it will go.
  void _trail(Canvas canvas, Size size) {
    final dot = Paint();
    for (var t = currentTick - 3; t < currentTick + 9; t += .22) {
      if (t < ball.start || (t - currentTick).abs() < .3) continue;
      final p = _ballPoint(t);
      if (p.dx > size.width) break;
      final ahead = t > currentTick;
      final fade = ahead
          ? 1 - (t - currentTick) / 9
          : 1 - (currentTick - t) / 3;
      dot.color = (ahead ? Colors.white : AppTheme.gold).withValues(
        alpha: .55 * fade,
      );
      canvas.drawCircle(p, 2.2, dot);
    }
  }

  void _ball(Canvas canvas) {
    final state = ball.at(currentTick);
    final v = BoardProjection.stringDepth(state.string);
    final scale = _board.scale(v);
    final ground = _board.project(_hitU, v);
    // Shadow shrinks and fades as the ball rises.
    final rise = (state.height / ball.maxHeight).clamp(0.0, 1.0);
    canvas.drawOval(
      Rect.fromCenter(
        center: ground,
        width: 30 * scale * (1 - .5 * rise),
        height: 9 * scale * (1 - .5 * rise),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: .5 * (1 - .6 * rise))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // Ring spreading from the note the ball just landed on.
    final since = state.sinceLanding;
    if (since != null && since < .9 && state.landed != null) {
      final finger = notes[state.landed!].finger;
      canvas.drawCircle(
        ground,
        (14 + since * 40) * scale,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * scale
          ..color = fingerColors[finger].withValues(
            alpha: .7 * (1 - since / .9),
          ),
      );
    }
    final radius = 16 * scale;
    final center = _board.project(
      _hitU,
      v,
      lift: state.height * _lift + radius,
    );
    // Squashed for a moment when it lands.
    final squash = since != null && since < .25 ? 1 - since / .25 : 0.0;
    final ballRect = Rect.fromCenter(
      center: center + Offset(0, radius * .18 * squash),
      width: radius * 2 * (1 + .22 * squash),
      height: radius * 2 * (1 - .18 * squash),
    );
    canvas
      ..drawOval(
        ballRect.inflate(6),
        Paint()
          ..color = AppTheme.gold.withValues(alpha: .45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      )
      ..drawOval(
        ballRect,
        Paint()
          ..shader = ui.Gradient.radial(
            ballRect.center - Offset(radius * .35, radius * .4),
            radius * 1.4,
            [Colors.white, const Color(0xFFFFF1C4), AppTheme.gold],
            [0, .45, 1],
          ),
      );
  }

  static const _verdictText = {
    Verdict.perfect: 'ممتاز',
    Verdict.early: 'مبكر',
    Verdict.late: 'متأخر',
    Verdict.missed: 'فائت',
  };

  /// Verdict words rising and fading above the hit line.
  void _feedback(Canvas canvas) {
    for (final mark in feedback) {
      final age = seconds - mark.shownAt;
      if (age < 0 || age > .9) continue;
      final v = BoardProjection.stringDepth(mark.string.toDouble());
      final at = _board.project(_hitU, v, lift: 44 + age * 60);
      final color = verdictColor(mark.verdict);
      final text = TextPainter(
        text: TextSpan(
          text: _verdictText[mark.verdict],
          style: TextStyle(
            fontFamily: 'IBM Plex Sans Arabic',
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: color.withValues(alpha: 1 - age / .9),
            shadows: const [Shadow(blurRadius: 6, color: Colors.black)],
          ),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      text.paint(canvas, at - Offset(text.width / 2, text.height / 2));
    }
  }

  @override
  bool shouldRepaint(HighwayPainter old) =>
      old.currentTick != currentTick ||
      old.seconds != seconds ||
      old.feedback.length != feedback.length ||
      old.waiting != waiting;
}

/// The whole song in one strip: colored dashes per string and the part
/// already played lit up.
class SongOverviewPainter extends CustomPainter {
  final List<GameNote> notes;
  final double progress, totalTicks;

  /// Verdict per note while the microphone scores, else null.
  final List<Verdict?>? verdicts;
  const SongOverviewPainter({
    this.verdicts,
    required this.notes,
    required this.progress,
    required this.totalTicks,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas
      ..drawRRect(rect, Paint()..color = const Color(0xFF0C0E0E))
      ..save()
      ..clipRRect(rect);
    final lane = (size.height - 8) / 6;
    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];
      final string = n.note.s - 1;
      final verdict = verdicts?[i];
      final x0 = n.absoluteTime / totalTicks * size.width;
      final x1 = (n.absoluteTime + n.note.d) / totalTicks * size.width;
      final played = x0 <= progress * size.width;
      canvas.drawLine(
        Offset(x0, 4 + lane * (string + .5)),
        Offset(math.max(x1 - 1, x0 + 1.5), 4 + lane * (string + .5)),
        Paint()
          ..color = verdict != null
              ? verdictColor(verdict)
              : fingerColors[n.finger].withValues(alpha: played ? .35 : .9)
          ..strokeWidth = math.max(1.5, lane * .7)
          ..strokeCap = StrokeCap.round,
      );
    }
    final at = progress * size.width;
    canvas
      ..drawRect(
        Rect.fromLTRB(0, 0, at, size.height),
        Paint()..color = AppTheme.gold.withValues(alpha: .12),
      )
      ..drawLine(
        Offset(at, 0),
        Offset(at, size.height),
        Paint()
          ..color = AppTheme.gold
          ..strokeWidth = 2,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(SongOverviewPainter old) => old.progress != progress;
}

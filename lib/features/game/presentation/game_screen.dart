import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/models/song.dart';
import '../../../core/theme/app_theme.dart';
import '../data/song_data.dart';

class GameNote {
  final Note note;
  final double absoluteTime;
  const GameNote(this.note, this.absoluteTime);
}

class GameScreen extends StatefulWidget {
  final Song song;
  const GameScreen({super.key, required this.song});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final List<GameNote> _notes;
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  double _currentTick = 0;
  double _speed = 1;
  bool _playing = true;
  static const _leadTicks = 6.0;
  double get _end => _notes.last.absoluteTime + _notes.last.note.d + _leadTicks;
  bool get _finished => _currentTick >= _end;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    var time = 0.0;
    _notes = [
      for (final note in rawSongData)
        (() {
          final result = GameNote(note, time);
          time += note.d;
          return result;
        })(),
    ];
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    // Ticker's elapsed time, rather than frame count, keeps 60/120 Hz displays in sync.
    final seconds =
        (elapsed - _lastElapsed).inMicroseconds /
        Duration.microsecondsPerSecond;
    _lastElapsed = elapsed;
    if (!_playing) return;
    setState(() {
      _currentTick = math.min(_end, _currentTick + seconds * 6 * _speed);
      if (_finished) {
        _playing = false;
        _ticker.stop();
      }
    });
  }

  void _toggle() {
    if (_finished) {
      _restart();
      return;
    }
    setState(() => _playing = !_playing);
    if (_playing) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  void _restart() {
    _ticker.stop();
    setState(() {
      _currentTick = 0;
      _playing = true;
      _lastElapsed = Duration.zero;
    });
    _ticker.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _playing) _toggle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF121212),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('game-back'),
                  tooltip: 'العودة للأغاني',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        widget.song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.cream,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'معاينة العزف',
                    style: TextStyle(color: AppTheme.gold, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              widget.song.hasChart
                  ? 'اعزف مع حركة النغمات • التقييم غير مفعّل'
                  : 'نغمات توضيحية • نوتة هذه الأغنية ستتوفر لاحقاً',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.cream, fontSize: 11),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Stack(
                children: [
                  Positioned.fill(
                    child: Semantics(
                      label: 'ستة أوتار مع نغمات متحركة وأرقام الحنق',
                      child: CustomPaint(
                        key: const ValueKey('guitar-board'),
                        painter: GamePainter(
                          notes: _notes,
                          currentTick: _currentTick,
                          leadTicks: _leadTicks,
                        ),
                      ),
                    ),
                  ),
                  if (!_playing)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: AppTheme.surface.withValues(alpha: .95),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _finished
                                  ? Icons.check_circle_outline
                                  : Icons.pause_circle_outline,
                              size: 40,
                              color: AppTheme.gold,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _finished ? 'انتهت المعاينة' : 'متوقف مؤقتاً',
                              style: const TextStyle(fontSize: 20),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _toggle,
                              child: Text(_finished ? 'إعادة العزف' : 'متابعة'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
            child: Column(
              children: [
                LinearProgressIndicator(
                  key: const ValueKey('session-progress'),
                  value: (_currentTick / _end).clamp(0, 1).toDouble(),
                  minHeight: 3,
                  backgroundColor: AppTheme.card,
                ),
                const SizedBox(height: 12),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        key: const ValueKey('game-restart'),
                        tooltip: 'إعادة من البداية',
                        onPressed: _restart,
                        icon: const Icon(Icons.replay_rounded),
                      ),
                      const SizedBox(width: 16),
                      FilledButton.icon(
                        key: const ValueKey('game-toggle'),
                        onPressed: _toggle,
                        icon: Icon(
                          _playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                        label: Text(_playing ? 'إيقاف' : 'متابعة'),
                      ),
                      const SizedBox(width: 16),
                      DropdownButton<double>(
                        value: _speed,
                        underline: const SizedBox(),
                        items: [
                          for (final speed in [.5, .75, 1.0, 1.25])
                            DropdownMenuItem(
                              value: speed,
                              child: Text(
                                '$speed×',
                                style: const TextStyle(color: AppTheme.cream),
                              ),
                            ),
                        ],
                        onChanged: (speed) {
                          if (speed != null) setState(() => _speed = speed);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class GamePainter extends CustomPainter {
  final List<GameNote> notes;
  final double currentTick, leadTicks;
  const GamePainter({
    required this.notes,
    required this.currentTick,
    required this.leadTicks,
  });
  static const colors = [
    Color(0xFF9B59B6),
    Color(0xFF2ECC71),
    Color(0xFFE67E22),
    Color(0xFF3498DB),
    Color(0xFFF1C40F),
    Color(0xFFE74C3C),
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final spacing = math.min(46.0, math.max(14.0, (size.height - 50) / 5));
    final startY = (size.height - spacing * 5) / 2;
    final hitX = size.width < 500 ? 54.0 : 100.0;
    final zoom = size.width < 500 ? 32.0 : 50.0;
    final stringPaint = Paint()..strokeWidth = 1.5;
    for (var i = 0; i < 6; i++) {
      final y = startY + i * spacing;
      stringPaint.color = colors[i].withValues(alpha: .35);
      canvas.drawLine(Offset(36, y), Offset(size.width, y), stringPaint);
      _text(
        canvas,
        ['e', 'B', 'G', 'D', 'A', 'E'][i],
        Offset(19, y),
        colors[i],
        12,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          hitX - 14,
          startY - 24,
          hitX + 14,
          startY + 5 * spacing + 24,
        ),
        const Radius.circular(10),
      ),
      Paint()..color = Colors.white.withValues(alpha: .045),
    );
    canvas.drawLine(
      Offset(hitX, startY - 24),
      Offset(hitX, startY + spacing * 5 + 24),
      Paint()
        ..color = Colors.white38
        ..strokeWidth = 2,
    );
    for (final gameNote in notes) {
      final x = hitX + (gameNote.absoluteTime + leadTicks - currentTick) * zoom;
      if (x < 36 || x > size.width + 20) continue;
      final index = gameNote.note.s - 1;
      if (index < 0 || index > 5) continue;
      final y = startY + index * spacing;
      final paint = Paint()..color = colors[index];
      canvas.drawCircle(
        Offset(x, y),
        15,
        paint..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      paint.maskFilter = null;
      canvas.drawCircle(Offset(x, y), 12, paint);
      _text(canvas, '${gameNote.note.f}', Offset(x, y), Colors.white, 12);
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset center,
    Color color,
    double size,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w700,
          fontFamily: 'IBM Plex Sans Arabic',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(GamePainter oldDelegate) =>
      oldDelegate.currentTick != currentTick || oldDelegate.notes != notes;
}

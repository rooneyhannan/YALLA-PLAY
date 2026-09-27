import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/models/song.dart';
import '../../../core/theme/app_theme.dart';
import '../data/ball_path.dart';
import '../data/song_data.dart';
import 'highway_painter.dart';

export 'highway_painter.dart' show GameNote;

class GameScreen extends StatefulWidget {
  final Song song;
  const GameScreen({super.key, required this.song});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _background = Color(0xFF101414);
  late final List<GameNote> _notes;
  late final BallPath _ball;
  late final Ticker _ticker;
  double _seconds = 0;
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
    _ball = BallPath(
      landings: [for (final n in _notes) n.absoluteTime + _leadTicks],
      strings: [for (final n in _notes) n.note.s - 1],
    );
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
      _seconds += seconds;
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
    backgroundColor: _background,
    body: SafeArea(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            Positioned.fill(
              child: Semantics(
                label: 'ستة أوتار مع نغمات متحركة وكرة تقفز من نغمة إلى نغمة',
                child: CustomPaint(
                  key: const ValueKey('guitar-board'),
                  painter: HighwayPainter(
                    notes: _notes,
                    ball: _ball,
                    currentTick: _currentTick,
                    leadTicks: _leadTicks,
                    totalTicks: _end,
                    seconds: _seconds,
                    background: _background,
                  ),
                ),
              ),
            ),
            Positioned(left: 0, right: 0, top: 0, child: _header()),
            Positioned(left: 0, right: 0, bottom: 0, child: _controls()),
            if (!_playing) Center(child: _pauseCard()),
          ],
        ),
      ),
    ),
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 6, 12, 0),
    child: Column(
      children: [
        Row(
          children: [
            IconButton(
              key: const ValueKey('game-back'),
              tooltip: 'العودة للأغاني',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 4),
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
                    style: const TextStyle(fontSize: 12, color: AppTheme.cream),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
        Text(
          widget.song.hasChart
              ? 'اعزف مع حركة النغمات • التقييم غير مفعّل'
              : 'نغمات توضيحية • نوتة هذه الأغنية ستتوفر لاحقاً',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.cream, fontSize: 11),
        ),
      ],
    ),
  );

  Widget _controls() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
    child: Row(
      children: [
        IconButton.filled(
          key: const ValueKey('game-toggle'),
          tooltip: _playing ? 'إيقاف مؤقت' : 'متابعة',
          onPressed: _toggle,
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.gold,
            foregroundColor: const Color(0xFF241A00),
          ),
          icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 30,
                width: double.infinity,
                child: CustomPaint(
                  painter: SongOverviewPainter(
                    notes: _notes,
                    progress: (_currentTick / _end).clamp(0, 1).toDouble(),
                    totalTicks: _end,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              LinearProgressIndicator(
                key: const ValueKey('session-progress'),
                value: (_currentTick / _end).clamp(0, 1).toDouble(),
                minHeight: 2,
                backgroundColor: Colors.transparent,
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('game-restart'),
          tooltip: 'إعادة من البداية',
          onPressed: _restart,
          icon: const Icon(Icons.replay_rounded),
        ),
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
  );

  Widget _pauseCard() => Container(
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
          _finished ? Icons.check_circle_outline : Icons.pause_circle_outline,
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
  );
}

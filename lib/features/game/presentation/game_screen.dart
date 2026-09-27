import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/models/song.dart';
import '../../../core/theme/app_theme.dart';
import '../../tuner/data/tuner_engine.dart';
import '../../tuner/data/tuning.dart';
import '../data/ball_path.dart';
import '../data/note_judge.dart';
import '../data/song_data.dart';
import 'highway_painter.dart';

export 'highway_painter.dart' show GameNote;

class GameScreen extends StatefulWidget {
  final Song song;
  final TunerEngine Function() engineFactory;
  const GameScreen({
    super.key,
    required this.song,
    this.engineFactory = createTunerEngine,
  });
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _background = Color(0xFF101414);
  static const _leadTicks = 6.0, _countdownSeconds = 3.0;

  /// Time from a pluck to its pitch reaching us: one analysis window.
  static const _micLatency = .08;

  /// How clearly an expected note must repeat to count while other strings
  /// ring; tuned on recordings so a semitone off does not pass.
  static const _presence = .6;
  late final List<GameNote> _notes;
  late final BallPath _ball;
  late final NoteJudge _judge;
  late final Ticker _ticker;
  late final TunerEngine _engine = widget.engineFactory();
  final _onsets = OnsetDetector();
  final _feedback = <FeedbackMark>[];
  double _seconds = 0, _currentTick = 0, _speed = 1, _countdown = 0;
  Duration _lastElapsed = Duration.zero;
  bool _started = false, _playing = false, _listening = false;
  double _level = 0;

  /// Tick of the last pluck, while its pitch may still settle.
  double? _pluckTick;

  /// The newest microphone frame, for checking the expected notes in it.
  List<double>? _frame;
  num _sampleRate = 48000;
  double get _end => _notes.last.absoluteTime + _notes.last.note.d + _leadTicks;
  bool get _finished => _currentTick >= _end;
  double get _ticksPerSecond => 6 * _speed;

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
    _judge = NoteJudge(
      starts: [for (final n in _notes) n.absoluteTime + _leadTicks],
      frequencies: [for (final n in _notes) noteFrequency(n.note)],
    );
    _ticker = createTicker(_onTick)..start();
  }

  /// Starts the song after a countdown; with [listen], the microphone
  /// scores the playing. Must run from a tap, for the browser's sake.
  Future<void> _start({required bool listen}) async {
    if (listen) {
      try {
        await _engine.start(_onPitch, onFrame: _onFrame);
        _listening = true;
      } on TunerException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تعذّر تشغيل الميكروفون. ستعمل الأغنية دون تقييم.'),
            ),
          );
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _started = true;
      _countdown = _countdownSeconds;
    });
  }

  void _onTick(Duration elapsed) {
    // Ticker's elapsed time, rather than frame count, keeps 60/120 Hz displays in sync.
    final seconds =
        (elapsed - _lastElapsed).inMicroseconds /
        Duration.microsecondsPerSecond;
    _lastElapsed = elapsed;
    setState(() {
      _seconds += seconds;
      if (_countdown > 0) {
        _countdown = math.max(0, _countdown - seconds);
        if (_countdown == 0) _playing = true;
        return;
      }
      if (!_playing) return;
      _currentTick = math.min(_end, _currentTick + seconds * _ticksPerSecond);
      if (_listening) {
        for (final i in _judge.expire(
          _currentTick,
          ticksPerSecond: _ticksPerSecond,
        )) {
          _feedback.add(
            FeedbackMark(Verdict.missed, _notes[i].note.s - 1, _seconds),
          );
        }
        _feedback.removeWhere((mark) => _seconds - mark.shownAt > 1);
      }
      if (_finished) _playing = false;
    });
  }

  void _onFrame(List<double> samples, num sampleRate) {
    _frame = samples;
    _sampleRate = sampleRate;
  }

  /// Whether the pluck sounds like [wanted]: the detected pitch matches, or
  /// the note is clearly there although other strings still ring.
  bool _sounds(double? heard, double wanted) =>
      (heard != null && pitchMatches(heard, wanted)) ||
      (_frame != null &&
          periodicityAt(_frame!, _sampleRate, wanted) >= _presence);

  void _onPitch(double? frequency, double level) {
    if (!mounted) return;
    _level = level;
    final frame = _frame;
    _frame = null;
    if (!_playing) return;
    if (_onsets.feed(level, frequency)) {
      _pluckTick = _currentTick - _micLatency * _ticksPerSecond;
    }
    final pluck = _pluckTick;
    if (pluck == null || (frequency == null && frame == null)) return;
    // The pitch settles a few readings after the attack; give it a moment.
    if (_currentTick - pluck > .3 * _ticksPerSecond) {
      _pluckTick = null;
      return;
    }
    _frame = frame;
    final index = _judge.pluckWhere(
      pluck,
      (wanted) => _sounds(frequency, wanted),
      ticksPerSecond: _ticksPerSecond,
    );
    _frame = null;
    if (index != null) {
      _pluckTick = null;
      setState(
        () => _feedback.add(
          FeedbackMark(
            _judge.verdicts[index]!,
            _notes[index].note.s - 1,
            _seconds,
          ),
        ),
      );
    }
  }

  void _toggle() {
    if (!_started) return;
    if (_finished) {
      _restart();
      return;
    }
    setState(() {
      _playing = !_playing;
      _countdown = 0;
    });
  }

  void _restart() {
    setState(() {
      _currentTick = 0;
      _playing = _started;
      _countdown = 0;
      _judge.reset();
      _feedback.clear();
      _pluckTick = null;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _playing) _toggle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engine.stop();
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
                    verdicts: _listening ? _judge.verdicts : null,
                    feedback: _feedback,
                  ),
                ),
              ),
            ),
            Positioned(left: 0, right: 0, top: 0, child: _header()),
            Positioned(left: 0, right: 0, bottom: 0, child: _controls()),
            if (!_started)
              Center(child: _startCard())
            else if (_countdown > 0)
              Center(child: _countdownNumber())
            else if (_finished && _listening)
              Center(child: _resultCard())
            else if (!_playing)
              Center(child: _pauseCard()),
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
            _listening ? _scoreBoard() : _previewChip(),
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

  Widget _previewChip() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: AppTheme.gold.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text(
      'معاينة العزف',
      style: TextStyle(color: AppTheme.gold, fontSize: 11),
    ),
  );

  /// Multiplier, score and a microphone light, as the playing is scored.
  Widget _scoreBoard() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.mic_rounded,
        size: 18,
        color: Color.lerp(
          Colors.white24,
          const Color(0xFF3CD98A),
          (_level * 12).clamp(0, 1).toDouble(),
        ),
      ),
      const SizedBox(width: 10),
      Text(
        '×${_judge.multiplier}',
        key: const ValueKey('game-multiplier'),
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppTheme.cream,
        ),
      ),
      const SizedBox(width: 14),
      Text(
        '${_judge.score}',
        key: const ValueKey('game-score'),
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: AppTheme.gold,
        ),
      ),
    ],
  );

  Widget _card(List<Widget> children) => Container(
    constraints: const BoxConstraints(maxWidth: 360),
    margin: const EdgeInsets.all(20),
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: AppTheme.surface.withValues(alpha: .96),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppTheme.border),
    ),
    child: Directionality(
      textDirection: TextDirection.rtl,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );

  Widget _startCard() => _card([
    const Icon(Icons.graphic_eq_rounded, size: 40, color: AppTheme.gold),
    const SizedBox(height: 10),
    const Text(
      'اعزف مع الكرة',
      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 8),
    const Text(
      'نستمع إلى عزفك عبر الميكروفون ونقيّم كل نغمة: الصوت الصحيح في الوقت الصحيح.',
      textAlign: TextAlign.center,
      style: TextStyle(color: AppTheme.cream, fontSize: 14),
    ),
    const SizedBox(height: 18),
    SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: const ValueKey('game-start'),
        onPressed: () => _start(listen: true),
        icon: const Icon(Icons.mic_rounded),
        label: const Text('ابدأ العزف'),
      ),
    ),
    const SizedBox(height: 6),
    TextButton(
      key: const ValueKey('game-start-preview'),
      onPressed: () => _start(listen: false),
      child: const Text('مشاهدة فقط، بدون ميكروفون'),
    ),
  ]);

  Widget _countdownNumber() => Text(
    '${_countdown.ceil()}',
    key: const ValueKey('game-countdown'),
    style: TextStyle(
      fontSize: 96,
      fontWeight: FontWeight.w700,
      color: AppTheme.gold.withValues(alpha: .4 + .6 * (_countdown % 1)),
      shadows: const [Shadow(blurRadius: 24, color: Colors.black)],
    ),
  );

  Widget _resultCard() {
    final judged = _judge.verdicts;
    int count(Verdict v) => judged.where((x) => x == v).length;
    return _card([
      Row(
        key: const ValueKey('game-stars'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 3; i++)
            Icon(
              i < _judge.stars ? Icons.star_rounded : Icons.star_border_rounded,
              size: 44,
              color: AppTheme.gold,
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        '${_judge.score} نقطة',
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: AppTheme.gold,
        ),
      ),
      Text(
        'الدقة ${(_judge.accuracy * 100).round()}٪ • أطول سلسلة ${_judge.bestStreak}',
        style: const TextStyle(color: AppTheme.cream),
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 14,
        alignment: WrapAlignment.center,
        children: [
          Text('ممتاز ${count(Verdict.perfect)}'),
          Text('مبكر ${count(Verdict.early)}'),
          Text('متأخر ${count(Verdict.late)}'),
          Text('فائت ${count(Verdict.missed)}'),
        ],
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: _restart,
              child: const Text('مرة أخرى'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('الأغاني'),
            ),
          ),
        ],
      ),
    ]);
  }
}

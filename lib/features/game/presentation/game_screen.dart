import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/models/song.dart';
import '../../../core/theme/app_theme.dart';
import '../../tuner/data/tuner_engine.dart';
import '../../tuner/data/tuning.dart';
import '../data/arrangement.dart';
import '../data/ball_path.dart';
import '../data/fingering.dart';
import '../data/note_judge.dart';
import '../data/song_chart.dart';
import '../data/sound_engine.dart';
import '../data/sound_scheduler.dart';
import '../data/synth.dart';
import 'hand_painter.dart';
import 'highway_painter.dart';

export 'highway_painter.dart' show GameNote;

/// Playing runs the song through and scores it; practice waits at every
/// note until it is played.
enum GameMode { play, practice }

class GameScreen extends StatefulWidget {
  final Song song;
  final SongChart chart;
  final TunerEngine Function() engineFactory;
  final SoundEngine Function() soundFactory;
  const GameScreen({
    super.key,
    required this.song,
    required this.chart,
    this.engineFactory = createTunerEngine,
    this.soundFactory = createSoundEngine,
  });
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _background = Color(0xFF101414);
  static const _countdownSeconds = 3.0;

  /// A beat and a half before the first note, to see it coming.
  late final double _leadTicks = widget.chart.ticksPerBeat * 1.5;

  /// Time from a pluck to its pitch reaching us: one analysis window.
  static const _micLatency = .08;

  /// How clearly an expected note must repeat to count while other strings
  /// ring; tuned on recordings so a semitone off does not pass.
  static const _presence = .6;

  /// How far ahead sounds are handed to the audio clock, in seconds.
  static const _soundAhead = .2;
  late final List<GameNote> _notes;
  late final BallPath _ball;
  late final NoteJudge _judge;
  late final Ticker _ticker;
  late final TunerEngine _engine = widget.engineFactory();
  late final SoundEngine _sound = widget.soundFactory();
  late final SoundScheduler _scheduler;
  bool _metronome = true, _backing = true;
  final _onsets = OnsetDetector();
  final _expected = ExpectedNoteDetector();
  final _feedback = <FeedbackMark>[];
  double _seconds = 0, _currentTick = 0, _speed = 1, _countdown = 0;
  Duration _lastElapsed = Duration.zero;

  /// Time since the last frame, so a pitch heard between two slow frames
  /// is placed exactly in the song, not at the older frame.
  final _sinceFrame = Stopwatch()..start();
  bool _started = false, _playing = false, _listening = false;
  GameMode _mode = GameMode.play;
  double _level = 0;

  /// Seconds practice has been waiting at the next note, or null while
  /// the song moves.
  double? _waited;

  /// Tick of the last pluck, while its pitch may still settle.
  double? _pluckTick;

  /// The newest microphone frame, for checking the expected notes in it.
  List<double>? _frame;
  num _sampleRate = 48000;
  double get _end => _notes.last.absoluteTime + _notes.last.note.d + _leadTicks;
  bool get _finished => _currentTick >= _end;
  double get _ticksPerSecond => widget.chart.ticksPerSecond * _speed;
  bool get _practicing => _listening && _mode == GameMode.practice;

  /// Song time for judging: stands still at a note practice waits at, so
  /// the waiting is counted in as lateness.
  double get _clock =>
      _currentTick +
      ((_waited ?? 0) +
              (_playing && !_finished
                  ? math.min(.25, _sinceFrame.elapsedMicroseconds / 1e6)
                  : 0)) *
          _ticksPerSecond;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final chart = widget.chart.notes;
    // Fingers the chart leaves open follow the one-finger-per-fret rule.
    final fingers = assignFingers([for (final n in chart) n.note]);
    _notes = [
      for (var i = 0; i < chart.length; i++)
        GameNote(
          chart[i].note,
          chart[i].tick.toDouble(),
          finger: chart[i].finger ?? fingers[i],
        ),
    ];
    _ball = BallPath(
      landings: [for (final n in _notes) n.absoluteTime + _leadTicks],
      strings: [for (final n in _notes) n.note.s - 1],
    );
    _judge = NoteJudge(
      starts: [for (final n in _notes) n.absoluteTime + _leadTicks],
      frequencies: [for (final n in _notes) noteFrequency(n.note)],
    );
    _scheduler = SoundScheduler(
      Arrangement.of(
        [
          for (final n in _notes)
            (
              start: n.absoluteTime + _leadTicks,
              length: n.note.d.toDouble(),
              frequency: noteFrequency(n.note),
            ),
        ],
        firstBeat: _leadTicks,
        end: _end,
        beatTicks: widget.chart.ticksPerBeat.toDouble(),
        barTicks: (widget.chart.ticksPerBeat * widget.chart.beatsPerBar)
            .toDouble(),
        ticksPerSecond: widget.chart.ticksPerSecond,
        chords: [
          for (final c in widget.chart.chords)
            (
              start: c.tick + _leadTicks,
              length: c.length.toDouble(),
              chord: c.chord,
            ),
        ],
      ).events,
    );
    _ticker = createTicker(_onTick)..start();
  }

  /// Starts the song after a countdown; with a [mode], the microphone
  /// scores the playing. Must run from a tap, for the browser's sake.
  Future<void> _start(GameMode? mode) async {
    // Before any await, so the browser sees it as started by the tap.
    final sound = _sound.start();
    if (mode != null) {
      _mode = mode;
      _judge.patient = mode == GameMode.practice;
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
    await sound;
    if (!mounted) return;
    setState(() {
      _started = true;
      _countdown = _countdownSeconds;
    });
    _countIn();
  }

  /// One click for each second of the countdown, stressed on the last.
  void _countIn() {
    final now = _sound.time;
    if (now == null || !_metronome) return;
    for (var i = 0; i < _countdownSeconds; i++) {
      _sound.play(
        i == _countdownSeconds - 1 ? Voice.accent : Voice.click,
        0,
        at: now + i,
        length: .05,
        gain: 1,
      );
    }
  }

  /// Which sounds play: the metronome and the backing by their switches,
  /// the melody only while nobody plays along, so the microphone never
  /// hears it.
  bool _audible(SoundEvent e) => switch (e.voice) {
    Voice.click || Voice.accent => _metronome,
    Voice.chord || Voice.bass => _backing,
    Voice.guitar => _backing && !_listening,
  };

  /// Starts the sounds over from the current tick, after a pause, a seek,
  /// a new speed or a switch.
  void _resound() {
    _sound.silence();
    _scheduler.seek(_currentTick);
  }

  void _onTick(Duration elapsed) {
    // Ticker's elapsed time, rather than frame count, keeps 60/120 Hz displays in sync.
    final seconds =
        (elapsed - _lastElapsed).inMicroseconds /
        Duration.microsecondsPerSecond;
    _lastElapsed = elapsed;
    _sinceFrame.reset();
    setState(() {
      _seconds += seconds;
      if (_countdown > 0) {
        _countdown = math.max(0, _countdown - seconds);
        if (_countdown == 0) {
          _playing = true;
          _scheduler.seek(_currentTick);
        }
        return;
      }
      if (!_playing) return;
      var next = _currentTick + seconds * _ticksPerSecond;
      final open = _practicing ? _judge.firstOpen : null;
      if (open != null && next >= _judge.starts[open]) {
        // Practice holds the song at the note until it is played.
        _waited =
            (_waited ?? 0) + (next - _judge.starts[open]) / _ticksPerSecond;
        next = _judge.starts[open];
      }
      _currentTick = math.min(_end, next);
      final now = _sound.time;
      if (now != null) {
        var until = _currentTick + _soundAhead * _ticksPerSecond;
        // While practice waits at a note, nothing after it may sound yet.
        final open = _practicing ? _judge.firstOpen : null;
        if (open != null) until = math.min(until, _judge.starts[open]);
        _scheduler.run(
          _sound,
          tick: _currentTick,
          until: until,
          now: now,
          ticksPerSecond: _ticksPerSecond,
          enabled: _audible,
        );
      }
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
    if (frame != null) _listenForNotes(frame, level);
    if (_onsets.feed(level, frequency)) {
      _pluckTick = _clock - _micLatency * _ticksPerSecond;
    }
    final pluck = _pluckTick;
    if (pluck == null || (frequency == null && frame == null)) return;
    // The pitch settles a few readings after the attack; give it a moment.
    if (_clock - pluck > .3 * _ticksPerSecond) {
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
    if (index != null) _hit(index);
  }

  /// Checks each note due about now for itself in [frame]: this still hears
  /// the guitar when the backing is louder than it.
  void _listenForNotes(List<double> frame, double rms) {
    final at = _clock - _micLatency * _ticksPerSecond;
    for (var i = _judge.firstOpen ?? _notes.length; i < _notes.length; i++) {
      if (_judge.verdicts[i] != null) continue;
      final offset = (at - _judge.starts[i]) / _ticksPerSecond;
      // Listened for a little before its early window, to learn how quiet
      // it was before the pluck.
      if (offset < -NoteJudge.earlyWindow - .3) break;
      if (offset > NoteJudge.lateWindow && !_practicing) continue;
      final frequency = _judge.frequencies[i];
      if (!_expected.heard(i, frame, _sampleRate, frequency, rms)) continue;
      if (_judge.pluckNote(i, at, ticksPerSecond: _ticksPerSecond)) {
        _hit(i);
        return;
      }
    }
  }

  void _hit(int index) {
    _pluckTick = null;
    setState(() {
      _waited = null;
      _feedback.add(
        FeedbackMark(
          _judge.verdicts[index]!,
          _notes[index].note.s - 1,
          _seconds,
        ),
      );
    });
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
    _resound();
  }

  void _restart() {
    setState(() {
      _currentTick = 0;
      _playing = _started;
      _countdown = 0;
      _judge.reset();
      _expected.reset();
      _feedback.clear();
      _pluckTick = null;
      _waited = null;
    });
    _resound();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _playing) _toggle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engine.stop();
    _sound.dispose();
    _ticker.dispose();
    super.dispose();
  }

  /// The note to finger now: the one practice waits at, else the one
  /// sounding or next to reach the hit line. Once a note is judged, the
  /// hand moves on to the next.
  int? get _currentNote {
    if (_practicing) return _judge.firstOpen;
    for (var i = 0; i < _notes.length; i++) {
      final n = _notes[i];
      if (_listening && _judge.verdicts[i] != null) continue;
      if (n.absoluteTime + _leadTicks + n.note.d > _currentTick) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _background,
    body: SafeArea(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: LayoutBuilder(
          builder: (context, box) {
            final portrait = box.maxHeight > box.maxWidth;
            final board = ClipRect(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Semantics(
                      label:
                          'ستة أوتار مع نغمات متحركة وكرة تقفز من نغمة إلى نغمة',
                      child: CustomPaint(
                        key: const ValueKey('guitar-board'),
                        painter: HighwayPainter(
                          notes: _notes,
                          ball: _ball,
                          currentTick: _currentTick,
                          leadTicks: _leadTicks,
                          beatTicks: widget.chart.ticksPerBeat.toDouble(),
                          barTicks:
                              (widget.chart.ticksPerBeat *
                                      widget.chart.beatsPerBar)
                                  .toDouble(),
                          totalTicks: _end,
                          seconds: _seconds,
                          background: _background,
                          verdicts: _listening ? _judge.verdicts : null,
                          feedback: _feedback,
                          waiting: _waited != null ? _judge.firstOpen : null,
                        ),
                      ),
                    ),
                  ),
                  if (_waited != null && _playing)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 8,
                      child: _waitingHint(),
                    ),
                ],
              ),
            );
            return Stack(
              children: [
                Column(
                  children: [
                    _header(),
                    // Portrait: the board above the hand; landscape: side by side.
                    Expanded(
                      child: portrait
                          ? Column(
                              children: [
                                Expanded(flex: 5, child: board),
                                Expanded(flex: 4, child: _handGuide()),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(child: board),
                                SizedBox(
                                  width: math.min(260, box.maxWidth * .28),
                                  child: _handGuide(),
                                ),
                              ],
                            ),
                    ),
                    _controls(),
                  ],
                ),
                if (!_started)
                  Center(child: SingleChildScrollView(child: _startCard()))
                else if (_countdown > 0)
                  Center(child: _countdownNumber())
                else if (_finished && _listening)
                  Center(child: SingleChildScrollView(child: _resultCard()))
                else if (!_playing)
                  Center(child: _pauseCard()),
              ],
            );
          },
        ),
      ),
    ),
  );

  /// The fretting hand with the finger for the current note lit, and what
  /// to play in words.
  Widget _handGuide() {
    final i = _currentNote;
    final note = i == null ? null : _notes[i];
    final finger = note?.finger ?? 0;
    var glow = 0.0;
    if (note != null) {
      final ahead =
          (note.absoluteTime + _leadTicks - _currentTick) / _ticksPerSecond;
      glow = ahead <= .1 ? 1 : (1 - ahead / 1.5).clamp(0, 1).toDouble();
      glow = (glow * 5).round() / 5;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Column(
        children: [
          // Its own layer: the hand repaints only when the finger or its
          // glow changes, not with every frame of the board.
          Expanded(
            child: RepaintBoundary(
              child: CustomPaint(
                key: const ValueKey('finger-hand'),
                size: Size.infinite,
                painter: HandPainter(finger: finger, glow: glow),
              ),
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                finger == 0
                    ? '${fingerNames[0]} • الوتر ${note.note.s}'
                    : '${fingerNames[finger]} • الوتر ${note.note.s} • العتبة ${note.note.f}',
                key: const ValueKey('finger-label'),
                textDirection: TextDirection.rtl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fingerColors[finger],
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

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
          !widget.song.hasChart
              ? 'نغمات توضيحية • نوتة هذه الأغنية ستتوفر لاحقاً'
              : !_listening
              ? 'اعزف مع حركة النغمات • التقييم غير مفعّل'
              : _practicing
              ? 'وضع التدريب • ننتظرك عند كل نغمة'
              : 'وضع العزف • كل نغمة تُقيَّم',
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
                    verdicts: _listening ? _judge.verdicts : null,
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
        _soundSwitch(
          key: 'game-metronome',
          on: _metronome,
          icon: Icons.av_timer_rounded,
          label: 'المترونوم',
          onChanged: (on) => _metronome = on,
        ),
        _soundSwitch(
          key: 'game-backing',
          on: _backing,
          icon: Icons.music_note_rounded,
          label: 'المرافقة الموسيقية',
          onChanged: (on) => _backing = on,
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
            if (speed == null) return;
            setState(() => _speed = speed);
            _resound();
          },
        ),
      ],
    ),
  );

  /// A sound on/off switch: gold while on, crossed out and dim while off.
  Widget _soundSwitch({
    required String key,
    required bool on,
    required IconData icon,
    required String label,
    required void Function(bool) onChanged,
  }) => IconButton(
    key: ValueKey(key),
    tooltip: on ? 'إيقاف $label' : 'تشغيل $label',
    isSelected: on,
    visualDensity: VisualDensity.compact,
    onPressed: () {
      setState(() => onChanged(!on));
      _resound();
    },
    icon: Stack(
      alignment: Alignment.center,
      children: [
        Icon(icon, color: on ? AppTheme.gold : Colors.white38),
        if (!on)
          Transform.rotate(
            angle: -.8,
            child: Container(width: 24, height: 2, color: Colors.white54),
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
      if (_practicing)
        Text(
          '${_judge.judged} / ${_notes.length}',
          key: const ValueKey('game-practice-count'),
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppTheme.gold,
          ),
        )
      else ...[
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
    ],
  );

  /// Tells which note practice waits for.
  Widget _waitingHint() {
    final note = _notes[_judge.firstOpen!].note;
    return Center(
      child: Container(
        key: const ValueKey('game-waiting'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: .9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: fingerColors[_notes[_judge.firstOpen!].finger],
          ),
        ),
        child: Text(
          'اعزف النغمة: الوتر ${note.s} • العتبة ${note.f}',
          textDirection: TextDirection.rtl,
          style: const TextStyle(fontSize: 14, color: AppTheme.cream),
        ),
      ),
    );
  }

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
      'نستمع إلى عزفك عبر الميكروفون: الصوت الصحيح في الوقت الصحيح.',
      textAlign: TextAlign.center,
      style: TextStyle(color: AppTheme.cream, fontSize: 14),
    ),
    const SizedBox(height: 6),
    const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.headphones_rounded, size: 16, color: AppTheme.gold),
        SizedBox(width: 6),
        Flexible(
          child: Text(
            'مع السماعات يكون التعرّف على عزفك أدق.',
            key: ValueKey('game-headphones-tip'),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.gold, fontSize: 12),
          ),
        ),
      ],
    ),
    const SizedBox(height: 18),
    SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: const ValueKey('game-start'),
        onPressed: () => _start(GameMode.play),
        icon: const Icon(Icons.mic_rounded),
        label: const Text('العزف'),
      ),
    ),
    const Text(
      'الأغنية كاملة دون توقف، وكل نغمة تُقيَّم.',
      textAlign: TextAlign.center,
      style: TextStyle(color: AppTheme.cream, fontSize: 12),
    ),
    const SizedBox(height: 12),
    SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const ValueKey('game-start-practice'),
        onPressed: () => _start(GameMode.practice),
        icon: const Icon(Icons.school_rounded),
        label: const Text('التدريب'),
      ),
    ),
    const Text(
      'تتوقف الأغنية عند كل نغمة حتى تعزفها صحيحة.',
      textAlign: TextAlign.center,
      style: TextStyle(color: AppTheme.cream, fontSize: 12),
    ),
    const SizedBox(height: 10),
    TextButton(
      key: const ValueKey('game-start-preview'),
      onPressed: () => _start(null),
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
    final practice = [
      const Icon(Icons.school_rounded, size: 40, color: perfectColor),
      const SizedBox(height: 8),
      const Text(
        'انتهى التدريب',
        key: ValueKey('game-practice-done'),
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      ),
      Text(
        'في الوقت ${count(Verdict.perfect)} من ${_notes.length}',
        style: const TextStyle(color: AppTheme.cream),
      ),
    ];
    return _card([
      if (_practicing)
        ...practice
      else ...[
        Row(
          key: const ValueKey('game-stars'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 3; i++)
              Icon(
                i < _judge.stars
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
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
      ],
      const SizedBox(height: 14),
      Wrap(
        spacing: 14,
        alignment: WrapAlignment.center,
        children: [
          Text(
            'ممتاز ${count(Verdict.perfect)}',
            style: const TextStyle(color: perfectColor),
          ),
          Text(
            'مبكر ${count(Verdict.early)}',
            style: const TextStyle(color: offTimeColor),
          ),
          Text(
            'متأخر ${count(Verdict.late)}',
            style: const TextStyle(color: offTimeColor),
          ),
          if (!_practicing)
            Text(
              'فائت ${count(Verdict.missed)}',
              style: const TextStyle(color: missedColor),
            ),
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

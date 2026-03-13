import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../models/song_data.dart';

class GameNote {
  final Note note;
  final double absoluteTime;

  GameNote(this.note, this.absoluteTime);
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late List<GameNote> _gameNotes;
  late Ticker _ticker;

  // Game State
  double _currentTick = 0.0;
  bool _isPlaying = false;

  // Configuration
  final double _zoom = 50.0;
  final double _hitLineX = 100.0;
  final double _startOffset = 500.0;
  final double _speed = 1.0; // Controls how fast _currentTick increases

  // String Colors (e, B, G, D, A, E)
  final List<Color> _stringColors = const [
    Colors.transparent, // 0 unused
    Color(0xFF9b59b6), // e (Purple)
    Color(0xFF2ecc71), // B (Green)
    Color(0xFFe67e22), // G (Orange)
    Color(0xFF3498db), // D (Blue)
    Color(0xFFf1c40f), // A (Yellow)
    Color(0xFFe74c3c), // E (Red)
  ];

  @override
  void initState() {
    super.initState();
    _initGameData();
    _ticker = createTicker(_onTick);
    // Start game automatically for smoother UX, or wait for user interaction
    _startGame();
  }

  void _initGameData() {
    _gameNotes = [];
    double currentAccumulatedTime = 0;

    for (var note in rawSongData) {
      _gameNotes.add(GameNote(note, currentAccumulatedTime));
      currentAccumulatedTime += note.d;
    }
  }

  void _onTick(Duration elapsed) {
    if (!_isPlaying) return;

    setState(() {
      // Increment tick based on frame rate or fixed step
      // Adjust this value to control overall game speed feel
      _currentTick += 0.1 * _speed; 

      // Stop if song ends
      if (_gameNotes.isNotEmpty &&
          _currentTick > _gameNotes.last.absoluteTime + 20) {
        _stopGame();
      }
    });
  }

  void _startGame() {
    setState(() {
      _isPlaying = true;
      _currentTick = 0;
    });
    _ticker.start();
  }

  void _stopGame() {
    _ticker.stop();
    setState(() {
      _isPlaying = false;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          // Game Board
          CustomPaint(
            painter: GamePainter(
              notes: _gameNotes,
              currentTick: _currentTick,
              zoom: _zoom,
              hitLineX: _hitLineX,
              startOffset: _startOffset,
              stringColors: _stringColors,
            ),
            size: Size.infinite,
          ),

          // Back Button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GamePainter extends CustomPainter {
  final List<GameNote> notes;
  final double currentTick;
  final double zoom;
  final double hitLineX;
  final double startOffset;
  final List<Color> stringColors;

  GamePainter({
    required this.notes,
    required this.currentTick,
    required this.zoom,
    required this.hitLineX,
    required this.startOffset,
    required this.stringColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double centerY = size.height / 2;
    final double stringSpacing = 40.0;
    final double totalHeight = stringSpacing * 5;
    final double startY = centerY - (totalHeight / 2);

    // 1. Draw Strings
    final Paint stringPaint = Paint()
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (int i = 1; i <= 6; i++) {
      final y = startY + (i - 1) * stringSpacing;
      stringPaint.color = stringColors[i].withOpacity(0.3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), stringPaint);
    }

    // 2. Draw Hit Line
    final Paint hitLinePaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = 4.0;

    canvas.drawLine(
      Offset(hitLineX, startY - 20),
      Offset(hitLineX, startY + totalHeight + 20),
      hitLinePaint,
    );

    // 3. Draw Notes
    for (var gameNote in notes) {
      // Calculate X based on provided logic
      // x = hitLineX + 500 + (note.absoluteTime * zoom) - (currentTick * zoom)
      // Note: Assuming 'speed' in prompt meant zoom or tick increment, 
      // used zoom here to match distance units.
      final double noteX = hitLineX + startOffset +
          (gameNote.absoluteTime * zoom) - (currentTick * zoom);

      // Culling
      if (noteX < -50 || noteX > size.width + 50) continue;

      final int stringIndex = gameNote.note.s;
      if (stringIndex < 1 || stringIndex > 6) continue;

      final double y = startY + (stringIndex - 1) * stringSpacing;
      final Color color = stringColors[stringIndex];

      // Draw Note Body
      final Paint notePaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      // Glow effect
      canvas.drawCircle(
        Offset(noteX, y),
        16,
        notePaint..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );

      // Solid circle
      notePaint.maskFilter = null;
      canvas.drawCircle(Offset(noteX, y), 12, notePaint);

      // Draw Fret Number
      final TextSpan span = TextSpan(
        text: gameNote.note.f.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
      final TextPainter tp = TextPainter(
        text: span,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(noteX - tp.width / 2, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) {
    return oldDelegate.currentTick != currentTick;
  }
}

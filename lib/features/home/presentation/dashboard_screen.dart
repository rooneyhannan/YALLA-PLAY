import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/design_widgets.dart';

class DashboardScreen extends StatelessWidget {
  final VoidCallback onSongs, onLearn, onStart;
  const DashboardScreen({
    super.key,
    required this.onSongs,
    required this.onLearn,
    required this.onStart,
  });
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const PageStorageKey('dashboard'),
    child: Column(
      children: [
        const ColoredBox(
          color: AppTheme.surface,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: TrialBanner(),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
              child: LayoutBuilder(
                builder: (context, c) {
                  final width = c.maxWidth >= 800
                      ? (c.maxWidth - 48) / 3
                      : c.maxWidth;
                  return Wrap(
                    spacing: 24,
                    runSpacing: 24,
                    children: [
                      SizedBox(
                        width: width,
                        height: 340,
                        child: _daily(context),
                      ),
                      SizedBox(
                        width: width,
                        height: 340,
                        child: _yourSongs(context),
                      ),
                      SizedBox(
                        width: width,
                        height: 340,
                        child: _courses(context),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _daily(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFF8A2BE2), Color(0xFF4B0082)],
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF8A2BE2).withValues(alpha: .18),
          blurRadius: 24,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: CustomPaint(
      painter: const GirihPainter(hexagons: true),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(
                    Icons.calendar_today_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                const Text(
                  'الجلسة\nاليومية',
                  style: TextStyle(
                    fontSize: 28,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .1),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Transform.rotate(
                      angle: -math.pi / 4,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.favorite_border_rounded,
                            color: Colors.white,
                            size: 45,
                          ),
                          const SizedBox(height: 9),
                          SizedBox(
                            width: 64,
                            height: 44,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: const DesignImage('s1_2.png'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('daily-start'),
                onPressed: onStart,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00FA9A),
                  foregroundColor: Colors.black,
                ),
                child: const Text('ابدأ', style: TextStyle(fontSize: 22)),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _yourSongs(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(24),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onSongs,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF00CED1), Color(0xFF008080)],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _RingsPainter())),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Text(
                    'أغانيك',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          children: [
                            _circle('s1_3.png', 80),
                            const SizedBox(width: 8),
                            _circle('s1_4.png', 130),
                            const SizedBox(width: 8),
                            _circle('s1_5.png', 80),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _circle(String image, double size) => Container(
    width: size,
    height: size,
    padding: const EdgeInsets.all(3),
    decoration: const BoxDecoration(
      color: AppTheme.gold,
      shape: BoxShape.circle,
    ),
    child: ClipOval(child: DesignImage(image)),
  );

  Widget _courses(BuildContext context) => Material(
    color: AppTheme.card,
    borderRadius: BorderRadius.circular(24),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onLearn,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'دورات الأغاني',
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00BFFF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'NEW',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const Text(
              'تعلم خطوة بخطوة',
              style: TextStyle(color: AppTheme.cream),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: const DesignImage('s1_6.png'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: const DesignImage('s1_7.png'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFF301F1F),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Center(
                              child: Text(
                                'Franz\nFerdinand',
                                textAlign: TextAlign.center,
                                textDirection: TextDirection.ltr,
                                style: TextStyle(
                                  color: Color(0xFFFF664D),
                                  fontSize: 22,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'عرض الكل',
                  style: TextStyle(
                    color: AppTheme.cream,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.arrow_back, color: AppTheme.cream, size: 20),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _RingsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..color = Colors.white.withValues(alpha: .07);
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width * .45,
      p,
    );
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width * .65,
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

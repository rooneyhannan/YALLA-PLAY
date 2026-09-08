import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class DesignImage extends StatelessWidget {
  final String name;
  final BoxFit fit;
  const DesignImage(this.name, {super.key, this.fit = BoxFit.cover});
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/design/$name',
    fit: fit,
    width: double.infinity,
    height: double.infinity,
    errorBuilder: (_, _, _) => const ColoredBox(
      color: AppTheme.card,
      child: Center(
        child: Icon(Icons.music_note, color: AppTheme.gold, size: 40),
      ),
    ),
  );
}

class PatternBackground extends StatelessWidget {
  final Widget child;
  const PatternBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: const GirihPainter(), child: child);
}

class GirihPainter extends CustomPainter {
  final bool hexagons;
  const GirihPainter({this.hexagons = false});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (hexagons ? Colors.white : AppTheme.gold).withValues(
        alpha: hexagons ? .17 : .035,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = hexagons ? 1.5 : 1;
    if (hexagons) {
      const radius = 48.0;
      for (double x = -radius; x < size.width + radius; x += radius * 1.5) {
        final col = ((x + radius) / (radius * 1.5)).round();
        for (
          double y = -radius + (col.isOdd ? radius * .866 : 0);
          y < size.height + radius;
          y += radius * 1.732
        ) {
          final path = Path();
          for (var i = 0; i < 6; i++) {
            final a = math.pi / 3 * i;
            final p = Offset(
              x + radius * math.cos(a),
              y + radius * math.sin(a),
            );
            if (i == 0) {
              path.moveTo(p.dx, p.dy);
            } else {
              path.lineTo(p.dx, p.dy);
            }
          }
          canvas.drawPath(path..close(), paint);
        }
      }
    } else {
      for (double x = 12; x < size.width; x += 32) {
        for (double y = 12; y < size.height; y += 32) {
          canvas.drawLine(Offset(x - 4, y), Offset(x + 4, y), paint);
          canvas.drawLine(Offset(x, y - 4), Offset(x, y + 4), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(GirihPainter oldDelegate) =>
      hexagons != oldDelegate.hexagons;
}

class SectionTitle extends StatelessWidget {
  final String title;
  final VoidCallback? onAll;
  const SectionTitle(this.title, {super.key, this.onAll});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18, top: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (onAll != null)
          TextButton(onPressed: onAll, child: const Text('عرض الكل')),
      ],
    ),
  );
}

void showPreviewInfo(
  BuildContext context, {
  String title = 'Yalla Guitar',
  String? message,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, color: AppTheme.gold, size: 36),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message ??
                  'هذه معاينة للتصميم. الاشتراكات والدروس الكاملة ستتوفر لاحقاً. يمكنك تجربة واجهة العزف الآن من مكتبة الأغاني.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.cream),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('حسناً'),
            ),
          ],
        ),
      ),
    ),
  );
}

class TrialBanner extends StatelessWidget {
  final bool outlined;
  const TrialBanner({super.key, this.outlined = false});
  @override
  Widget build(BuildContext context) {
    void action() => showPreviewInfo(context, title: 'التجربة المجانية');
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: outlined
          ? OutlinedButton.icon(
              onPressed: action,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.gold,
                side: const BorderSide(color: AppTheme.border),
              ),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('ابدأ النسخة التجريبية المجانية'),
            )
          : FilledButton(
              onPressed: action,
              child: const Text('ابدأ النسخة التجريبية المجانية'),
            ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// عدّاد خطر دائري (قوس 270°) برسم مخصص، يتحرك عند ظهور النتيجة.
class RiskGauge extends StatelessWidget {
  const RiskGauge({
    super.key,
    required this.score,
    required this.color,
    this.size = 170,
  });

  final int score;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(score),
      tween: Tween<double>(begin: 0, end: score / 100),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _GaugePainter(v, color),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(v * 100).round()}',
                    style: TextStyle(
                      fontSize: size * 0.30,
                      fontWeight: FontWeight.w900,
                      color: color,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'من 100',
                    style: TextStyle(color: C.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.value, this.color);

  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final rect = Rect.fromLTWH(
      stroke,
      stroke,
      size.width - stroke * 2,
      size.height - stroke * 2,
    );
    const start = math.pi * 0.75;
    const sweepAll = math.pi * 1.5;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = C.surface2;
    canvas.drawArc(rect, start, sweepAll, false, track);

    if (value <= 0) return;

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke + 6
      ..strokeCap = StrokeCap.round
      ..color = alpha(color, 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawArc(rect, start, sweepAll * value, false, glow);

    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, start, sweepAll * value, false, fg);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value || old.color != color;
}

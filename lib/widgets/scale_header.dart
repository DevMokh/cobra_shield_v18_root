import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// ترويسة بنمط "حراشف الكوبرا" (شبكة سداسية) مرسومة بالكود: لا صور ولا حقوق.
class ScaleHeader extends StatelessWidget {
  const ScaleHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.shield_rounded,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0C2E22), C.bg],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _HexPainter(alpha(C.emerald, 0.10))),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, top + 22, 20, 26),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [C.emerald, Color(0xFF12A56E)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: alpha(C.emerald, 0.35),
                        blurRadius: 22,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(icon, color: C.onAccent, size: 32),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: C.text,
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(color: C.muted, fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HexPainter extends CustomPainter {
  _HexPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const r = 18.0;
    final w = r * 1.7320508;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    var row = 0;
    while (row * r * 1.5 < size.height + r * 2) {
      final y = row * r * 1.5;
      final offset = row.isOdd ? w / 2 : 0.0;
      for (var x = -w + offset; x < size.width + w; x += w) {
        _hex(canvas, Offset(x, y), r, paint);
      }
      row++;
    }
  }

  void _hex(Canvas canvas, Offset o, double r, Paint p) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final a = math.pi / 3 * i + math.pi / 6;
      final pt = Offset(o.dx + r * math.cos(a), o.dy + r * math.sin(a));
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _HexPainter old) => old.color != color;
}

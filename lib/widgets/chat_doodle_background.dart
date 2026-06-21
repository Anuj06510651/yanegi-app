import 'dart:math';
import 'package:flutter/material.dart';

class ChatDoodleBackground extends StatelessWidget {
  const ChatDoodleBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: CustomPaint(painter: _DoodlePainter()),
    );
  }
}

class _DoodlePainter extends CustomPainter {
  const _DoodlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = Colors.white.withAlpha(14)
      ..style = PaintingStyle.fill;

    final rng = Random(42);
    final cellSize = 52.0;
    final cols = (size.width / cellSize).ceil() + 1;
    final rows = (size.height / cellSize).ceil() + 1;

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final cx = col * cellSize + rng.nextDouble() * 20 - 10;
        final cy = row * cellSize + rng.nextDouble() * 20 - 10;
        final shape = rng.nextInt(28);
        _drawDoodle(canvas, cx, cy, shape, paint, fillPaint, rng);
      }
    }

    // Scatter small dots
    for (var i = 0; i < (size.width * size.height / 800).round(); i++) {
      final dx = rng.nextDouble() * size.width;
      final dy = rng.nextDouble() * size.height;
      canvas.drawCircle(Offset(dx, dy), rng.nextDouble() * 1.2 + 0.3, fillPaint);
    }
  }

  void _drawDoodle(Canvas canvas, double cx, double cy, int shape,
      Paint stroke, Paint fill, Random rng) {
    final s = 7.0 + rng.nextDouble() * 5;
    final o = Offset(cx, cy);

    switch (shape) {
      case 0: // star
        _drawStar(canvas, o, s, stroke);
        break;
      case 1: // circle
        canvas.drawCircle(o, s, stroke);
        break;
      case 2: // heart
        _drawHeart(canvas, o, s * 0.8, stroke);
        break;
      case 3: // smiley
        canvas.drawCircle(o, s, stroke);
        canvas.drawCircle(Offset(cx - s * 0.3, cy - s * 0.2), 1, fill);
        canvas.drawCircle(Offset(cx + s * 0.3, cy - s * 0.2), 1, fill);
        _drawArc(canvas, o, s * 0.5, 0.2, 2.9, stroke);
        break;
      case 4: // camera
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: s * 2, height: s * 1.4), const Radius.circular(2)), stroke);
        canvas.drawCircle(o, s * 0.45, stroke);
        break;
      case 5: // music note
        canvas.drawCircle(Offset(cx, cy + s * 0.5), s * 0.35, fill);
        canvas.drawLine(Offset(cx + s * 0.35, cy + s * 0.5), Offset(cx + s * 0.35, cy - s * 0.8), stroke);
        break;
      case 6: // envelope
        canvas.drawRect(Rect.fromCenter(center: o, width: s * 2, height: s * 1.3), stroke);
        canvas.drawLine(Offset(cx - s, cy - s * 0.65), o, stroke);
        canvas.drawLine(Offset(cx + s, cy - s * 0.65), o, stroke);
        break;
      case 7: // lightning bolt
        final path = Path()
          ..moveTo(cx, cy - s)
          ..lineTo(cx - s * 0.4, cy)
          ..lineTo(cx + s * 0.15, cy)
          ..lineTo(cx - s * 0.1, cy + s);
        canvas.drawPath(path, stroke);
        break;
      case 8: // planet
        canvas.drawCircle(o, s * 0.7, stroke);
        canvas.drawOval(Rect.fromCenter(center: o, width: s * 2.2, height: s * 0.5), stroke);
        break;
      case 9: // cloud
        canvas.drawCircle(Offset(cx - s * 0.5, cy), s * 0.55, stroke);
        canvas.drawCircle(Offset(cx + s * 0.5, cy), s * 0.55, stroke);
        canvas.drawCircle(Offset(cx, cy - s * 0.4), s * 0.6, stroke);
        break;
      case 10: // speech bubble
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy - 2), width: s * 2, height: s * 1.2), const Radius.circular(4)), stroke);
        final tail = Path()
          ..moveTo(cx - s * 0.3, cy + s * 0.6 - 2)
          ..lineTo(cx - s * 0.5, cy + s)
          ..lineTo(cx, cy + s * 0.6 - 2);
        canvas.drawPath(tail, stroke);
        break;
      case 11: // game controller
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: s * 2.2, height: s), const Radius.circular(4)), stroke);
        canvas.drawLine(Offset(cx - s * 0.5, cy - s * 0.15), Offset(cx - s * 0.5, cy + s * 0.15), stroke);
        canvas.drawLine(Offset(cx - s * 0.65, cy), Offset(cx - s * 0.35, cy), stroke);
        canvas.drawCircle(Offset(cx + s * 0.5, cy), 1.5, fill);
        break;
      case 12: // pizza slice
        final pizza = Path()
          ..moveTo(cx, cy - s)
          ..lineTo(cx - s * 0.7, cy + s * 0.6)
          ..lineTo(cx + s * 0.7, cy + s * 0.6)
          ..close();
        canvas.drawPath(pizza, stroke);
        break;
      case 13: // book
        canvas.drawRect(Rect.fromCenter(center: Offset(cx - 1, cy), width: s * 1.4, height: s * 1.8), stroke);
        canvas.drawLine(Offset(cx - 1, cy - s * 0.9), Offset(cx - 1, cy + s * 0.9), stroke);
        break;
      case 14: // trophy / cup
        _drawArc(canvas, Offset(cx, cy - s * 0.2), s * 0.7, 0, pi, stroke);
        canvas.drawLine(Offset(cx, cy + s * 0.5), Offset(cx, cy + s * 0.8), stroke);
        canvas.drawLine(Offset(cx - s * 0.4, cy + s * 0.8), Offset(cx + s * 0.4, cy + s * 0.8), stroke);
        break;
      case 15: // diamond
        final diamond = Path()
          ..moveTo(cx, cy - s)
          ..lineTo(cx + s * 0.7, cy)
          ..lineTo(cx, cy + s)
          ..lineTo(cx - s * 0.7, cy)
          ..close();
        canvas.drawPath(diamond, stroke);
        break;
      case 16: // bicycle
        canvas.drawCircle(Offset(cx - s * 0.6, cy + s * 0.3), s * 0.45, stroke);
        canvas.drawCircle(Offset(cx + s * 0.6, cy + s * 0.3), s * 0.45, stroke);
        canvas.drawLine(Offset(cx - s * 0.6, cy + s * 0.3), Offset(cx, cy - s * 0.3), stroke);
        canvas.drawLine(Offset(cx, cy - s * 0.3), Offset(cx + s * 0.6, cy + s * 0.3), stroke);
        break;
      case 17: // glasses
        canvas.drawCircle(Offset(cx - s * 0.5, cy), s * 0.4, stroke);
        canvas.drawCircle(Offset(cx + s * 0.5, cy), s * 0.4, stroke);
        canvas.drawLine(Offset(cx - s * 0.1, cy), Offset(cx + s * 0.1, cy), stroke);
        break;
      case 18: // flower
        for (var i = 0; i < 5; i++) {
          final a = i * pi * 2 / 5;
          canvas.drawCircle(Offset(cx + cos(a) * s * 0.5, cy + sin(a) * s * 0.5), s * 0.3, stroke);
        }
        canvas.drawCircle(o, s * 0.2, fill);
        break;
      case 19: // rocket
        canvas.drawOval(Rect.fromCenter(center: o, width: s * 0.8, height: s * 2), stroke);
        canvas.drawLine(Offset(cx - s * 0.4, cy + s * 0.7), Offset(cx - s * 0.7, cy + s), stroke);
        canvas.drawLine(Offset(cx + s * 0.4, cy + s * 0.7), Offset(cx + s * 0.7, cy + s), stroke);
        break;
      case 20: // pencil
        canvas.drawRect(Rect.fromLTWH(cx - s * 0.15, cy - s * 0.8, s * 0.3, s * 1.5), stroke);
        final tip = Path()
          ..moveTo(cx - s * 0.15, cy + s * 0.7)
          ..lineTo(cx, cy + s)
          ..lineTo(cx + s * 0.15, cy + s * 0.7);
        canvas.drawPath(tip, stroke);
        break;
      case 21: // flag
        canvas.drawLine(Offset(cx - s * 0.5, cy - s), Offset(cx - s * 0.5, cy + s), stroke);
        canvas.drawRect(Rect.fromLTWH(cx - s * 0.5, cy - s, s * 1.2, s * 0.8), stroke);
        break;
      case 22: // gift box
        canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy + s * 0.15), width: s * 1.6, height: s * 1.2), stroke);
        canvas.drawLine(Offset(cx, cy - s * 0.45), Offset(cx, cy + s * 0.75), stroke);
        canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy - s * 0.6), width: s * 1.8, height: s * 0.35), stroke);
        break;
      case 23: // wifi
        for (var i = 1; i <= 3; i++) {
          _drawArc(canvas, Offset(cx, cy + s * 0.3), s * 0.35 * i, pi + 0.5, pi * 2 - 0.5, stroke);
        }
        canvas.drawCircle(Offset(cx, cy + s * 0.3), 1.5, fill);
        break;
      case 24: // hamburger
        _drawArc(canvas, o, s * 0.8, pi, 2 * pi, stroke);
        canvas.drawLine(Offset(cx - s * 0.8, cy), Offset(cx + s * 0.8, cy), stroke);
        canvas.drawLine(Offset(cx - s * 0.75, cy + s * 0.35), Offset(cx + s * 0.75, cy + s * 0.35), stroke);
        _drawArc(canvas, Offset(cx, cy + s * 0.35), s * 0.75, 0, pi, stroke);
        break;
      case 25: // cat face
        canvas.drawCircle(o, s * 0.7, stroke);
        // ears
        canvas.drawLine(Offset(cx - s * 0.55, cy - s * 0.45), Offset(cx - s * 0.7, cy - s), stroke);
        canvas.drawLine(Offset(cx + s * 0.55, cy - s * 0.45), Offset(cx + s * 0.7, cy - s), stroke);
        canvas.drawCircle(Offset(cx - s * 0.25, cy - s * 0.15), 1, fill);
        canvas.drawCircle(Offset(cx + s * 0.25, cy - s * 0.15), 1, fill);
        break;
      case 26: // peace sign
        canvas.drawCircle(o, s * 0.8, stroke);
        canvas.drawLine(Offset(cx, cy - s * 0.8), Offset(cx, cy + s * 0.8), stroke);
        canvas.drawLine(o, Offset(cx - s * 0.55, cy + s * 0.55), stroke);
        canvas.drawLine(o, Offset(cx + s * 0.55, cy + s * 0.55), stroke);
        break;
      default: // small X
        canvas.drawLine(Offset(cx - 3, cy - 3), Offset(cx + 3, cy + 3), stroke);
        canvas.drawLine(Offset(cx + 3, cy - 3), Offset(cx - 3, cy + 3), stroke);
    }
  }

  void _drawStar(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 5; i++) {
      final outerAngle = -pi / 2 + i * 2 * pi / 5;
      final innerAngle = outerAngle + pi / 5;
      final outerPt = Offset(center.dx + cos(outerAngle) * r, center.dy + sin(outerAngle) * r);
      final innerPt = Offset(center.dx + cos(innerAngle) * r * 0.45, center.dy + sin(innerAngle) * r * 0.45);
      if (i == 0) {
        path.moveTo(outerPt.dx, outerPt.dy);
      } else {
        path.lineTo(outerPt.dx, outerPt.dy);
      }
      path.lineTo(innerPt.dx, innerPt.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawHeart(Canvas canvas, Offset center, double s, Paint paint) {
    final path = Path()
      ..moveTo(center.dx, center.dy + s * 0.7)
      ..cubicTo(center.dx - s * 1.2, center.dy - s * 0.2, center.dx - s * 0.5, center.dy - s, center.dx, center.dy - s * 0.3)
      ..cubicTo(center.dx + s * 0.5, center.dy - s, center.dx + s * 1.2, center.dy - s * 0.2, center.dx, center.dy + s * 0.7);
    canvas.drawPath(path, paint);
  }

  void _drawArc(Canvas canvas, Offset center, double radius, double startAngle, double endAngle, Paint paint) {
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, endAngle - startAngle, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

import 'package:flutter/material.dart';

class GoogleLogoIcon extends StatelessWidget {
  final double size;

  const GoogleLogoIcon({
    super.key,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GoogleLogoPainter(),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  static const Color _blue = Color(0xFF4285F4);
  static const Color _red = Color(0xFFEA4335);
  static const Color _yellow = Color(0xFFFBBC05);
  static const Color _green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw the "G" shape using a combination of arcs and rectangles
    // This creates the official Google logo appearance

    // Blue right vertical bar
    final bluePath = Path()
      ..addArc(
        Rect.fromCircle(center: center, radius: radius),
        -0.261799, // -15 degrees
        1.309, // 75 degrees arc
      );

    final bluePaint = Paint()
      ..color = _blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.22
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(bluePath, bluePaint);

    // Red top-left arc
    final redPath = Path()
      ..addArc(
        Rect.fromCircle(center: center, radius: radius),
        1.309, // 75 degrees
        1.309, // 75 degrees arc
      );

    final redPaint = Paint()
      ..color = _red
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.22
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(redPath, redPaint);

    // Yellow bottom-left arc
    final yellowPath = Path()
      ..addArc(
        Rect.fromCircle(center: center, radius: radius),
        2.618, // 150 degrees
        1.309, // 75 degrees arc
      );

    final yellowPaint = Paint()
      ..color = _yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.22
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(yellowPath, yellowPaint);

    // Green bottom-right arc
    final greenPath = Path()
      ..addArc(
        Rect.fromCircle(center: center, radius: radius),
        3.927, // 225 degrees
        1.309, // 75 degrees arc
      );

    final greenPaint = Paint()
      ..color = _green
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.22
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(greenPath, greenPaint);

    // Blue horizontal bar in the middle
    final barHeight = size.width * 0.2;
    final barWidth = size.width * 0.4;
    final barLeft = center.dx + (size.width * 0.05);
    final barTop = center.dy - (barHeight / 2);

    final barPaint = Paint()
      ..color = _blue
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(barLeft, barTop, barWidth, barHeight),
        Radius.circular(barHeight / 2),
      ),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

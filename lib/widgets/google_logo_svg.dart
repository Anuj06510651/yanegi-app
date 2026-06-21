import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class GoogleLogoSvg extends StatelessWidget {
  final bool grayscale;

  const GoogleLogoSvg({
    super.key,
    this.grayscale = false,
  });

  @override
  Widget build(BuildContext context) {
    // Base64 decoded SVG content as a string
    // This is the official Google logo SVG
    return CustomPaint(
      painter: _GoogleLogoSvgPainter(grayscale: grayscale),
      size: const Size(18, 18),
    );
  }
}

class _GoogleLogoSvgPainter extends CustomPainter {
  final bool grayscale;

  _GoogleLogoSvgPainter({required this.grayscale});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = ui.Offset(size.width / 24.0, size.height / 24.0);
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..color = grayscale ? const Color(0xFF999999) : const Color(0xFF000000);

    void drawPath(Path path, Color color) {
      paint.color = grayscale ? const Color(0xFF999999) : color;
      canvas.drawPath(path, paint);
    }

    Path transform(Path path) {
      final matrix = Float64List.fromList(<double>[
        scale.dx, 0, 0, 0,
        0, scale.dy, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
      ]);
      return path.transform(matrix);
    }

    Path blue = Path()
      ..moveTo(22.56, 12.25)
      ..cubicTo(22.56, 11.47, 22.49, 10.72, 22.36, 10.0)
      ..lineTo(12.0, 10.0)
      ..lineTo(12.0, 14.26)
      ..lineTo(17.92, 14.26)
      ..cubicTo(17.66, 15.63, 16.88, 16.79, 15.71, 17.57)
      ..lineTo(15.71, 20.34)
      ..lineTo(19.28, 20.34)
      ..cubicTo(21.36, 18.42, 22.56, 15.6, 22.56, 12.25)
      ..close();

    Path green = Path()
      ..moveTo(12.0, 23.0)
      ..cubicTo(14.97, 23.0, 17.46, 22.02, 19.28, 20.34)
      ..lineTo(15.71, 17.57)
      ..cubicTo(14.73, 18.23, 13.48, 18.63, 12.0, 18.63)
      ..cubicTo(9.14, 18.63, 6.71, 16.7, 5.84, 14.1)
      ..lineTo(2.18, 14.1)
      ..lineTo(2.18, 16.94)
      ..cubicTo(3.99, 20.53, 7.7, 23.0, 12.0, 23.0)
      ..close();

    Path yellow = Path()
      ..moveTo(5.84, 14.09)
      ..cubicTo(5.62, 13.43, 5.49, 12.73, 5.49, 12.0)
      ..cubicTo(5.49, 11.27, 5.62, 10.57, 5.84, 9.91)
      ..lineTo(5.84, 7.07)
      ..lineTo(2.18, 7.07)
      ..cubicTo(1.43, 8.55, 1.0, 10.22, 1.0, 12.0)
      ..cubicTo(1.0, 13.78, 1.43, 15.45, 2.18, 16.93)
      ..lineTo(5.03, 14.71)
      ..lineTo(5.84, 14.09)
      ..close();

    Path red = Path()
      ..moveTo(12.0, 5.38)
      ..cubicTo(13.62, 5.38, 15.06, 5.94, 16.21, 7.02)
      ..lineTo(19.36, 3.87)
      ..cubicTo(17.45, 2.09, 14.97, 1.0, 12.0, 1.0)
      ..cubicTo(7.7, 1.0, 3.99, 3.47, 2.18, 7.07)
      ..lineTo(5.84, 9.91)
      ..cubicTo(6.71, 7.31, 9.14, 5.38, 12.0, 5.38)
      ..close();

    drawPath(transform(red), const Color(0xFFEA4335));
    drawPath(transform(yellow), const Color(0xFFFBBC05));
    drawPath(transform(green), const Color(0xFF34A853));
    drawPath(transform(blue), const Color(0xFF4285F4));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

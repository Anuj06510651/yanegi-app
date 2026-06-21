import 'package:flutter/material.dart';

class GoogleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final String label;

  const GoogleSignInButton({
    super.key,
    this.onPressed,
    this.isLoading = false,
    this.label = 'Continue with Google',
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null || isLoading;

    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: isDisabled ? null : onPressed,
          borderRadius: BorderRadius.circular(24),
          hoverColor: isDisabled ? null : const Color(0xFFF8F9FA),
          splashColor: isDisabled ? null : Colors.black.withOpacity(0.05),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: const Color(0xFFDADCE0),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDisabled ? Colors.grey : const Color(0xFF1F1F1F),
                      ),
                    ),
                  )
                else
                  _buildGoogleLogoSvg(),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF1F1F1F),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Roboto',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleLogoSvg() {
    return SizedBox(
      width: 24,
      height: 24,
      child: CustomPaint(
        painter: _GoogleLogoSvgPainter(),
      ),
    );
  }
}

class _GoogleLogoSvgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;

    // Blue path: M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z
    final bluePath = Path()
      ..moveTo(22.56 * scale, 12.25 * scale)
      ..cubicTo(22.56 * scale, 11.47 * scale, 22.49 * scale, 10.72 * scale,
          22.36 * scale, 10 * scale)
      ..lineTo(12 * scale, 10 * scale)
      ..lineTo(12 * scale, 14.26 * scale)
      ..lineTo(17.92 * scale, 14.26 * scale)
      ..cubicTo(17.66 * scale, 15.63 * scale, 16.88 * scale, 16.79 * scale,
          15.71 * scale, 17.57 * scale)
      ..lineTo(15.71 * scale, 20.34 * scale)
      ..lineTo(19.28 * scale, 20.34 * scale)
      ..cubicTo(21.36 * scale, 18.42 * scale, 22.56 * scale, 15.6 * scale,
          22.56 * scale, 12.25 * scale)
      ..close();

    canvas.drawPath(
      bluePath,
      Paint()
        ..color = const Color(0xFF4285F4)
        ..style = PaintingStyle.fill,
    );

    // Green path: M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z
    final greenPath = Path()
      ..moveTo(12 * scale, 23 * scale)
      ..cubicTo(14.97 * scale, 23 * scale, 17.46 * scale, 22.02 * scale,
          19.28 * scale, 20.34 * scale)
      ..lineTo(15.71 * scale, 17.57 * scale)
      ..cubicTo(14.73 * scale, 18.23 * scale, 13.48 * scale, 18.63 * scale,
          12 * scale, 18.63 * scale)
      ..cubicTo(9.14 * scale, 18.63 * scale, 6.71 * scale, 16.7 * scale,
          5.84 * scale, 14.09 * scale)
      ..lineTo(2.18 * scale, 14.09 * scale)
      ..lineTo(2.18 * scale, 16.93 * scale)
      ..cubicTo(3.99 * scale, 20.53 * scale, 7.7 * scale, 23 * scale,
          12 * scale, 23 * scale)
      ..close();

    canvas.drawPath(
      greenPath,
      Paint()
        ..color = const Color(0xFF34A853)
        ..style = PaintingStyle.fill,
    );

    // Yellow path: M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z
    final yellowPath = Path()
      ..moveTo(5.84 * scale, 14.09 * scale)
      ..cubicTo(5.62 * scale, 13.43 * scale, 5.49 * scale, 12.73 * scale,
          5.49 * scale, 12 * scale)
      ..cubicTo(5.49 * scale, 11.27 * scale, 5.62 * scale, 10.57 * scale,
          5.84 * scale, 9.91 * scale)
      ..lineTo(5.84 * scale, 7.07 * scale)
      ..lineTo(2.18 * scale, 7.07 * scale)
      ..cubicTo(1.43 * scale, 8.55 * scale, 1 * scale, 10.22 * scale, 1 * scale,
          12 * scale)
      ..cubicTo(1 * scale, 13.78 * scale, 1.43 * scale, 15.45 * scale,
          2.18 * scale, 16.93 * scale)
      ..lineTo(5.03 * scale, 14.71 * scale)
      ..lineTo(5.84 * scale, 14.09 * scale)
      ..close();

    canvas.drawPath(
      yellowPath,
      Paint()
        ..color = const Color(0xFFFBBC05)
        ..style = PaintingStyle.fill,
    );

    // Red path: M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z
    final redPath = Path()
      ..moveTo(12 * scale, 5.38 * scale)
      ..cubicTo(13.62 * scale, 5.38 * scale, 15.06 * scale, 5.94 * scale,
          16.21 * scale, 7.02 * scale)
      ..lineTo(19.36 * scale, 3.87 * scale)
      ..cubicTo(17.45 * scale, 2.09 * scale, 14.97 * scale, 1 * scale,
          12 * scale, 1 * scale)
      ..cubicTo(7.7 * scale, 1 * scale, 3.99 * scale, 3.47 * scale,
          2.18 * scale, 7.07 * scale)
      ..lineTo(5.84 * scale, 9.91 * scale)
      ..cubicTo(6.71 * scale, 7.31 * scale, 9.14 * scale, 5.38 * scale,
          12 * scale, 5.38 * scale)
      ..close();

    canvas.drawPath(
      redPath,
      Paint()
        ..color = const Color(0xFFEA4335)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

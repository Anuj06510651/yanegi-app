import 'package:flutter/material.dart';

class BackgroundLayer extends StatelessWidget {
  final Widget child;
  final bool showGradient;

  const BackgroundLayer({
    super.key,
    required this.child,
    this.showGradient = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background image placeholder (solid color for now)
        Container(
          color: const Color(0xFF0A0A0F),
        ),
        // Dark gradient overlay
        if (showGradient)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withAlpha(60),
                  Colors.black.withAlpha(120),
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),
        // Content
        child,
      ],
    );
  }
}

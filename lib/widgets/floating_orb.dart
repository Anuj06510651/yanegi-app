import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../theme/yanegi_theme.dart';

/// Floating AI companion orb with breathing animation
/// Acts as the primary action trigger, feels alive and responsive
class FloatingOrb extends StatefulWidget {
  final VoidCallback? onTap;
  final double size;
  final bool isActive;

  const FloatingOrb({
    super.key,
    this.onTap,
    this.size = 64.0,
    this.isActive = false,
  });

  @override
  State<FloatingOrb> createState() => _FloatingOrbState();
}

class _FloatingOrbState extends State<FloatingOrb>
    with TickerProviderStateMixin {
  late AnimationController _breathController;
  late AnimationController _tapController;
  late AnimationController _rotateController;

  late Animation<double> _breathAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _expandAnimation;
  late Animation<double> _rotateAnimation;

  @override
  void initState() {
    super.initState();

    // Slow breathing animation - feels alive
    _breathController = AnimationController(
      duration: YanegiDurations.breathing,
      vsync: this,
    )..repeat(reverse: true);

    _breathAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _breathController, curve: YanegiCurves.gentle),
    );

    _glowAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _breathController, curve: YanegiCurves.gentle),
    );

    // Tap interaction
    _tapController = AnimationController(
      duration: YanegiDurations.standard,
      vsync: this,
    );

    _expandAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _tapController, curve: YanegiCurves.spring),
    );

    // Subtle rotation for inner elements
    _rotateController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();

    _rotateAnimation = Tween<double>(
      begin: 0,
      end: 2 * math.pi,
    ).animate(_rotateController);
  }

  @override
  void dispose() {
    _breathController.dispose();
    _tapController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (!mounted) return;
    _tapController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    if (!mounted) return;
    _tapController.reverse();
    widget.onTap?.call();
  }

  void _handleTapCancel() {
    if (!mounted) return;
    _tapController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        key: ValueKey(
            'floating_orb_breath_tap_rotate_${widget.size.toStringAsFixed(1)}'),
        animation: Listenable.merge([
          _breathController,
          _tapController,
          _rotateController,
        ]),
        builder: (context, child) {
          final scale = _breathAnimation.value * _expandAnimation.value;

          return SizedBox(
            width: widget.size * 2,
            height: widget.size * 2,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer glow rings
                ...List.generate(3, (index) {
                  final ringScale = 1.0 + (index * 0.3);
                  final opacity = 0.15 - (index * 0.04);
                  return Transform.scale(
                    scale: scale * ringScale,
                    child: Container(
                      width: widget.size,
                      height: widget.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: YanegiColors.primary.withValues(
                            alpha: opacity * _glowAnimation.value,
                          ),
                          width: 2,
                        ),
                      ),
                    ),
                  );
                }),

                // Main glow
                Transform.scale(
                  scale: scale,
                  child: Container(
                    width: widget.size * 1.5,
                    height: widget.size * 1.5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: YanegiColors.primary.withValues(
                            alpha: 0.4 * _glowAnimation.value,
                          ),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                        BoxShadow(
                          color: YanegiColors.tertiary.withValues(
                            alpha: 0.2 * _glowAnimation.value,
                          ),
                          blurRadius: 50,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ),

                // Orb body
                Transform.scale(
                  scale: scale,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.3, -0.3),
                        colors: [
                          YanegiColors.primary.withAlpha((0.9 * 255).toInt()),
                          YanegiColors.primary,
                          YanegiColors.secondary,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: YanegiColors.primary.withValues(
                            alpha: 0.5,
                          ),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Inner rotating gradient
                        Transform.rotate(
                          angle: _rotateAnimation.value,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: SweepGradient(
                                colors: [
                                  Colors.transparent,
                                  YanegiColors.tertiary.withValues(
                                    alpha: 0.3,
                                  ),
                                  Colors.transparent,
                                  YanegiColors.secondary.withValues(
                                    alpha: 0.2,
                                  ),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Highlight
                        Positioned(
                          top: widget.size * 0.15,
                          left: widget.size * 0.2,
                          child: Container(
                            width: widget.size * 0.25,
                            height: widget.size * 0.15,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(100),
                              color:
                                  Colors.white.withAlpha((0.4 * 255).toInt()),
                            ),
                          ),
                        ),

                        // Center icon
                        Center(
                          child: Icon(
                            Icons.auto_awesome,
                            color: Colors.white.withAlpha((0.9 * 255).toInt()),
                            size: widget.size * 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

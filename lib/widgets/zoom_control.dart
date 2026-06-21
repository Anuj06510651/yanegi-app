import 'package:flutter/material.dart';
import 'dart:ui';
import '../theme/yanegi_theme.dart';

/// Vertical pill-shaped zoom control
/// Minimal visual weight, blends with premium UI
class ZoomControl extends StatefulWidget {
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final double? currentZoom;
  final double minZoom;
  final double maxZoom;

  const ZoomControl({
    super.key,
    this.onZoomIn,
    this.onZoomOut,
    this.currentZoom,
    this.minZoom = 1.0,
    this.maxZoom = 20.0,
  });

  @override
  State<ZoomControl> createState() => _ZoomControlState();
}

class _ZoomControlState extends State<ZoomControl> {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(YanegiRadius.pill),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          width: 44,
          decoration: BoxDecoration(
            color: YanegiColors.surfaceGlass.withAlpha((0.7 * 255).toInt()),
            borderRadius: BorderRadius.circular(YanegiRadius.pill),
            border: Border.all(
              color: Colors.white.withAlpha((0.08 * 255).toInt()),
              width: 1,
            ),
            boxShadow: YanegiShadows.softElevation,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ZoomButton(icon: Icons.add, onTap: widget.onZoomIn, isTop: true),
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: Colors.white.withAlpha((0.1 * 255).toInt()),
              ),
              _ZoomButton(
                icon: Icons.remove,
                onTap: widget.onZoomOut,
                isTop: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isTop;

  const _ZoomButton({required this.icon, this.onTap, required this.isTop});

  @override
  State<_ZoomButton> createState() => _ZoomButtonState();
}

class _ZoomButtonState extends State<_ZoomButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: YanegiDurations.micro,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.9,
    ).animate(CurvedAnimation(parent: _controller, curve: YanegiCurves.smooth));

    _colorAnimation = ColorTween(
      begin: YanegiColors.textSecondary,
      end: YanegiColors.accentCyan,
    ).animate(CurvedAnimation(parent: _controller, curve: YanegiCurves.smooth));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (!mounted) return;
        _controller.forward();
      },
      onTapUp: (_) {
        if (!mounted) return;
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () {
        if (!mounted) return;
        _controller.reverse();
      },
      child: AnimatedBuilder(
        key: ValueKey('zoom_control_button_${widget.icon.codePoint}'),
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              child: Icon(widget.icon, color: _colorAnimation.value, size: 20),
            ),
          );
        },
      ),
    );
  }
}

/// Location button to center on user
class LocationButton extends StatefulWidget {
  final VoidCallback? onTap;
  final bool isTracking;

  const LocationButton({super.key, this.onTap, this.isTracking = false});

  @override
  State<LocationButton> createState() => _LocationButtonState();
}

class _LocationButtonState extends State<LocationButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: YanegiDurations.fast,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (!mounted) return;
        _controller.forward();
      },
      onTapUp: (_) {
        if (!mounted) return;
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () {
        if (!mounted) return;
        _controller.reverse();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(YanegiRadius.pill),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: AnimatedBuilder(
            key: ValueKey('location_button_press_${widget.isTracking}'),
            animation: _controller,
            builder: (context, child) {
              return Transform.scale(
                scale: 1.0 - (_controller.value * 0.1),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: YanegiColors.surfaceGlass
                        .withAlpha((0.7 * 255).toInt()),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withAlpha((0.08 * 255).toInt()),
                      width: 1,
                    ),
                    boxShadow: YanegiShadows.softElevation,
                  ),
                  child: Icon(
                    widget.isTracking
                        ? Icons.my_location
                        : Icons.location_searching,
                    color: widget.isTracking
                        ? YanegiColors.accentCyan
                        : YanegiColors.textSecondary,
                    size: 20,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

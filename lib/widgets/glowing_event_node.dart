import 'package:flutter/material.dart';

class GlowingEventNode extends StatefulWidget {
  final String emoji;
  final Color color;
  final bool pulse;

  const GlowingEventNode({
    super.key,
    required this.emoji,
    required this.color,
    this.pulse = true,
  });

  @override
  State<GlowingEventNode> createState() => _GlowingEventNodeState();
}

class _GlowingEventNodeState extends State<GlowingEventNode>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulseController;
  Animation<double>? _pulseAnimation;

  void _configurePulse({required bool shouldPulse}) {
    if (shouldPulse) {
      _pulseController ??= AnimationController(
        duration: const Duration(milliseconds: 2000),
        vsync: this,
      );
      _pulseAnimation ??= Tween<double>(begin: 1.0, end: 1.2).animate(
        CurvedAnimation(parent: _pulseController!, curve: Curves.easeInOut),
      );
      if (mounted && !(_pulseController?.isAnimating ?? false)) {
        _pulseController?.repeat();
      }
      return;
    }

    _pulseController?.stop();
  }

  @override
  void initState() {
    super.initState();
    _configurePulse(shouldPulse: widget.pulse);
  }

  @override
  void didUpdateWidget(covariant GlowingEventNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pulse != widget.pulse) {
      _configurePulse(shouldPulse: widget.pulse);
    }
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final node = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.color.withAlpha(200),
        border: Border.all(
          color: Colors.white.withAlpha(120),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.color.withAlpha(150),
            blurRadius: 16,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: widget.color.withAlpha(80),
            blurRadius: 24,
            spreadRadius: 8,
          ),
        ],
      ),
      child: Center(
        child: Text(
          widget.emoji,
          style: const TextStyle(fontSize: 24),
        ),
      ),
    );

    if (!widget.pulse) {
      return node;
    }

    return ScaleTransition(
      scale: _pulseAnimation ?? const AlwaysStoppedAnimation<double>(1.0),
      child: node,
    );
  }
}

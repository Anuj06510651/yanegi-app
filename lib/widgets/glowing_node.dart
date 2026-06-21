import 'package:flutter/material.dart';
import '../theme/yanegi_theme.dart';

/// A glowing node representing an event location on the map
/// Pulses with varying intensity based on activity level
class GlowingNode extends StatefulWidget {
  final double size;
  final Color color;
  final double activityLevel; // 0.0 to 1.0
  final VoidCallback? onTap;
  final String? label;

  const GlowingNode({
    super.key,
    this.size = 24.0,
    this.color = YanegiColors.accentCyan,
    this.activityLevel = 0.5,
    this.onTap,
    this.label,
  });

  @override
  State<GlowingNode> createState() => _GlowingNodeState();
}

class _GlowingNodeState extends State<GlowingNode>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _tapController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();

    // Pulse animation - continuous breathing
    _pulseController = AnimationController(
      duration: Duration(
        milliseconds: (YanegiDurations.pulse.inMilliseconds /
                (0.5 + widget.activityLevel * 0.5))
            .round(),
      ),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(
      begin: 0.85,
      end: 1.0 + (widget.activityLevel * 0.15),
    ).animate(
      CurvedAnimation(parent: _pulseController, curve: YanegiCurves.gentle),
    );

    // Tap feedback animation
    _tapController = AnimationController(
      duration: YanegiDurations.fast,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _tapController, curve: YanegiCurves.spring),
    );

    _glowAnimation = Tween<double>(begin: 1.0, end: 2.0).animate(
      CurvedAnimation(parent: _tapController, curve: YanegiCurves.smooth),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _tapController.dispose();
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
    final baseSize = widget.size * (0.8 + widget.activityLevel * 0.4);

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        key: ValueKey(
            'glowing_node_main_${widget.label ?? 'unlabeled'}_${widget.size.toStringAsFixed(1)}'),
        animation: Listenable.merge([_pulseController, _tapController]),
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: SizedBox(
              width: baseSize * 3,
              height: baseSize * 3,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer ripple aura
                  _buildRipple(baseSize * 2.5, 0.08 * widget.activityLevel),
                  _buildRipple(baseSize * 2.0, 0.12 * widget.activityLevel),
                  _buildRipple(baseSize * 1.5, 0.18 * widget.activityLevel),

                  // Glow layer
                  Container(
                    width: baseSize * _pulseAnimation.value * 1.8,
                    height: baseSize * _pulseAnimation.value * 1.8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: YanegiShadows.glow(
                        widget.color,
                        intensity: _glowAnimation.value * widget.activityLevel,
                      ),
                    ),
                  ),

                  // Core node
                  Container(
                    width: baseSize * _pulseAnimation.value,
                    height: baseSize * _pulseAnimation.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          widget.color,
                          widget.color.withAlpha((0.7 * 255).toInt()),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: widget.color.withAlpha((0.5 * 255).toInt()),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),

                  // Inner bright core
                  Container(
                    width: baseSize * _pulseAnimation.value * 0.4,
                    height: baseSize * _pulseAnimation.value * 0.4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withAlpha((0.8 * 255).toInt()),
                    ),
                  ),

                  // Label if provided
                  if (widget.label != null)
                    Positioned(
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: YanegiColors.surface
                              .withAlpha((0.9 * 255).toInt()),
                          borderRadius: BorderRadius.circular(YanegiRadius.sm),
                        ),
                        child: Text(
                          widget.label!,
                          style: const TextStyle(
                            fontSize: 10,
                            color: YanegiColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRipple(double size, double opacity) {
    return AnimatedBuilder(
      key: ValueKey(
          'glowing_node_ripple_${widget.label ?? 'unlabeled'}_${size.toStringAsFixed(1)}'),
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: size * _pulseAnimation.value,
          height: size * _pulseAnimation.value,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.color.withValues(alpha: opacity),
              width: 1.5,
            ),
          ),
        );
      },
    );
  }
}

/// Multiple nodes cluster for showing activity hotspots
class NodeCluster extends StatelessWidget {
  final List<NodeData> nodes;
  final Function(NodeData)? onNodeTap;

  const NodeCluster({super.key, required this.nodes, this.onNodeTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: nodes.map((node) {
        return Positioned(
          left: node.position.dx,
          top: node.position.dy,
          child: GlowingNode(
            size: node.size,
            color: node.color,
            activityLevel: node.activityLevel,
            label: node.label,
            onTap: () => onNodeTap?.call(node),
          ),
        );
      }).toList(),
    );
  }
}

class NodeData {
  final Offset position;
  final double size;
  final Color color;
  final double activityLevel;
  final String? label;
  final String? id;

  const NodeData({
    required this.position,
    this.size = 20.0,
    this.color = YanegiColors.accentCyan,
    this.activityLevel = 0.5,
    this.label,
    this.id,
  });
}

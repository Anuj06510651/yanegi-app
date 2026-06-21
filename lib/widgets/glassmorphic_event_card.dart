import 'package:flutter/material.dart';
import '../theme/yanegi_theme.dart';

class GlassmorphicEventCard extends StatefulWidget {
  final String icon;
  final String title;
  final String time;
  final String location;
  final int spotsLeft;
  final VoidCallback? onTap;

  const GlassmorphicEventCard({
    super.key,
    required this.icon,
    required this.title,
    required this.time,
    required this.location,
    required this.spotsLeft,
    this.onTap,
  });

  @override
  State<GlassmorphicEventCard> createState() => _GlassmorphicEventCardState();
}

class _GlassmorphicEventCardState extends State<GlassmorphicEventCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onTapDown() {
    _scaleController.forward();
  }

  void _onTapUp() {
    _scaleController.reverse();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: (_) => _onTapDown(),
        onTapUp: (_) => _onTapUp(),
        onTapCancel: () => _scaleController.reverse(),
        child: Container(
          width: 150,
          height: 145,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(YanegiRadius.lg),
            color: YanegiColors.surface.withAlpha(200),
            border: Border.all(
              color: YanegiColors.accentCyan.withAlpha(60),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(100),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: YanegiColors.primary.withAlpha(20),
                blurRadius: 16,
                offset: const Offset(0, 0),
              ),
            ],
          ),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(YanegiRadius.lg),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      YanegiColors.primary.withAlpha(10),
                      YanegiColors.secondary.withAlpha(5),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(YanegiRadius.md),
                        color: YanegiColors.primary.withAlpha(180),
                        boxShadow: [
                          BoxShadow(
                            color: YanegiColors.primary.withAlpha(100),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          widget.icon,
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 11,
                          color: YanegiColors.accentCyan.withAlpha(180),
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            widget.time,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${widget.spotsLeft} spots',
                      style: TextStyle(
                        color: YanegiColors.accentCyan.withAlpha(200),
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

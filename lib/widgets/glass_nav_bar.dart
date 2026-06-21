import 'package:flutter/material.dart';
import 'dart:ui';
import '../theme/yanegi_theme.dart';

/// Minimal floating glass navigation bar
/// iOS-style with frosted glass effect and subtle animations
class GlassNavBar extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;

  const GlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<GlassNavBar> createState() => _GlassNavBarState();
}

class _GlassNavBarState extends State<GlassNavBar> {
  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      margin: EdgeInsets.fromLTRB(
        YanegiSpacing.lg,
        YanegiSpacing.md,
        YanegiSpacing.lg,
        YanegiSpacing.md + (bottomPadding > 0 ? bottomPadding * 0.35 : 8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(YanegiRadius.xl),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: YanegiSpacing.md),
            decoration: BoxDecoration(
              color: YanegiColors.surfaceGlass.withAlpha((0.75 * 255).toInt()),
              borderRadius: BorderRadius.circular(YanegiRadius.xl),
              border: Border.all(
                color: Colors.white.withAlpha((0.1 * 255).toInt()),
                width: 1,
              ),
              boxShadow: YanegiShadows.glassElevation,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.explore_outlined,
                  activeIcon: Icons.explore,
                  isActive: widget.currentIndex == 0,
                  onTap: () => widget.onTap(0),
                ),
                _NavItem(
                  icon: Icons.search_outlined,
                  activeIcon: Icons.search,
                  isActive: widget.currentIndex == 1,
                  onTap: () => widget.onTap(1),
                ),
                // Space for floating orb
                const SizedBox(width: 64),
                _NavItem(
                  icon: Icons.chat_bubble_outline,
                  activeIcon: Icons.chat_bubble,
                  isActive: widget.currentIndex == 2,
                  onTap: () => widget.onTap(2),
                ),
                _NavItem(
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  isActive: widget.currentIndex == 3,
                  onTap: () => widget.onTap(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final IconData activeIcon;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: YanegiDurations.fast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.85,
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
        widget.onTap();
      },
      onTapCancel: () {
        if (!mounted) return;
        _controller.reverse();
      },
      child: AnimatedBuilder(
        key: ValueKey('glass_nav_item_press_${widget.icon.codePoint}'),
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: AnimatedContainer(
              duration: YanegiDurations.fast,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isActive
                    ? YanegiColors.primary.withAlpha((0.2 * 255).toInt())
                    : Colors.transparent,
              ),
              child: AnimatedSwitcher(
                duration: YanegiDurations.fast,
                child: Icon(
                  widget.isActive ? widget.activeIcon : widget.icon,
                  key: ValueKey(widget.isActive),
                  color: widget.isActive
                      ? YanegiColors.primary
                      : YanegiColors.textSecondary,
                  size: 24,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

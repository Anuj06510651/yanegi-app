part of '../../../screens/map_screen.dart';

class _ExploreCardInteraction extends StatefulWidget {
  const _ExploreCardInteraction({
    required this.child,
    required this.onTap,
    required this.onLongPress,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_ExploreCardInteraction> createState() =>
      _ExploreCardInteractionState();
}

class _ExploreCardInteractionState extends State<_ExploreCardInteraction> {
  bool _isPressed = false;

  void _setPressed(bool value) {
    if (!mounted || _isPressed == value) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);

    return GestureDetector(
      onTapDown: (_) {
        _setPressed(true);
        HapticFeedback.lightImpact();
      },
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(_isPressed ? 110 : 70),
                blurRadius: _isPressed ? 16 : 10,
                spreadRadius: _isPressed ? 0.6 : 0,
                offset: Offset(0, _isPressed ? 6 : 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: radius,
              splashColor: Colors.white.withAlpha(26),
              highlightColor: Colors.white.withAlpha(14),
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

part of '../../../screens/map_screen.dart';

class _UserLocationMarker extends StatefulWidget {
  const _UserLocationMarker();

  @override
  State<_UserLocationMarker> createState() => _UserLocationMarkerState();
}

class _UserLocationMarkerState extends State<_UserLocationMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (mounted) {
      _pulseController.repeat();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const markerBlue = Color(0xFF3B82F6);
    return AnimatedBuilder(
      key: const ValueKey('map_user_location_pulse'),
      animation: _pulseController,
      builder: (context, _) {
        final t = _pulseController.value;
        final ringScale = 0.75 + (t * 0.7);
        final ringOpacity = (1 - t).clamp(0.0, 1.0);
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: ringScale,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: markerBlue.withOpacity(0.25 * ringOpacity),
                ),
              ),
            ),
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: markerBlue,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: markerBlue.withAlpha(130),
                    blurRadius: 10,
                    spreadRadius: 2,
                  )
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

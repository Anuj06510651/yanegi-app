import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Fullscreen photo viewer with LinkedIn-style gestures.
///
/// - Pinch + double-tap to zoom
/// - Drag-to-dismiss when not zoomed (swipe down or up)
/// - Hero animation in/out (when [heroTag] is provided)
/// - Branded fallback for empty/failed URLs
/// - Dark scrim that fades with the dismiss gesture
class AppImageViewer extends StatefulWidget {
  const AppImageViewer({
    super.key,
    required this.imageUrl,
    this.heroTag,
    this.isCircular = false,
  });

  final String imageUrl;
  final Object? heroTag;

  /// If true, the hero-source widget is circular (a profile avatar); the
  /// viewer keeps the image rectangular but uses a softer entry animation.
  final bool isCircular;

  /// Convenience opener — returns immediately if [imageUrl] is empty.
  static Future<void> open(
    BuildContext context, {
    required String imageUrl,
    Object? heroTag,
    bool isCircular = false,
  }) {
    final trimmed = imageUrl.trim();
    if (trimmed.isEmpty) return Future.value();
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => AppImageViewer(
          imageUrl: trimmed,
          heroTag: heroTag,
          isCircular: isCircular,
        ),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  @override
  State<AppImageViewer> createState() => _AppImageViewerState();
}

class _AppImageViewerState extends State<AppImageViewer>
    with SingleTickerProviderStateMixin {
  final TransformationController _transform = TransformationController();
  late final AnimationController _resetCtrl;
  Animation<Matrix4>? _resetAnim;

  Offset _dragOffset = Offset.zero;
  double _dragOpacity = 1.0;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _resetCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        if (_resetAnim != null) {
          _transform.value = _resetAnim!.value;
        }
      });
    _transform.addListener(_onTransformChanged);
  }

  void _onTransformChanged() {
    final scale = _transform.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.05;
    if (zoomed != _isZoomed) {
      setState(() => _isZoomed = zoomed);
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _resetCtrl.dispose();
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
    super.dispose();
  }

  void _handleDoubleTap(TapDownDetails details) {
    final currentScale = _transform.value.getMaxScaleOnAxis();
    final Matrix4 target;
    if (currentScale > 1.05) {
      target = Matrix4.identity();
    } else {
      final position = details.localPosition;
      target = Matrix4.identity()
        ..translate(-position.dx * 1.5, -position.dy * 1.5)
        ..scale(2.5);
    }
    _resetAnim = Matrix4Tween(begin: _transform.value, end: target).animate(
      CurvedAnimation(parent: _resetCtrl, curve: Curves.easeOutCubic),
    );
    _resetCtrl
      ..value = 0
      ..forward();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_isZoomed) return;
    setState(() {
      _dragOffset += Offset(0, details.delta.dy);
      final progress = (_dragOffset.dy.abs() / 280).clamp(0.0, 1.0);
      _dragOpacity = (1.0 - progress).clamp(0.0, 1.0);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_isZoomed) return;
    if (_dragOffset.dy.abs() > 140 ||
        details.primaryVelocity != null &&
            details.primaryVelocity!.abs() > 800) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _dragOffset = Offset.zero;
      _dragOpacity = 1.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scrim = Colors.black.withOpacity(_dragOpacity.clamp(0.0, 1.0));

    final imageContent = _ViewerImage(imageUrl: widget.imageUrl);

    final hero = widget.heroTag == null
        ? imageContent
        : Hero(tag: widget.heroTag!, child: imageContent);

    return Scaffold(
      backgroundColor: scrim,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          onDoubleTapDown: _handleDoubleTap,
          onDoubleTap: () {},
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 50),
              transform: Matrix4.identity()
                ..translate(_dragOffset.dx, _dragOffset.dy),
              child: InteractiveViewer(
                transformationController: _transform,
                minScale: 1.0,
                maxScale: 4.0,
                clipBehavior: Clip.none,
                child: hero,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewerImage extends StatelessWidget {
  const _ViewerImage({required this.imageUrl});
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.contain,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (_, __) => const SizedBox(
        width: 60,
        height: 60,
        child: Center(
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2,
          ),
        ),
      ),
      errorWidget: (_, __, ___) => const _ViewerError(),
    );
  }
}

class _ViewerError extends StatelessWidget {
  const _ViewerError();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: Colors.white70, size: 44),
          SizedBox(height: 12),
          Text(
            'Unable to load image.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

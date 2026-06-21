part of '../../../screens/chat/chat_thread_screen.dart';

class _SwipeToReplyRow extends StatefulWidget {
  const _SwipeToReplyRow({required this.child, this.onReply});
  final Widget child;
  final VoidCallback? onReply;

  @override
  State<_SwipeToReplyRow> createState() => _SwipeToReplyRowState();
}

class _SwipeToReplyRowState extends State<_SwipeToReplyRow> {
  double _dragX = 0;
  bool _triggered = false;
  // WhatsApp-style: activate after a short ~28 px pull so the finger
  // never needs to reach the screen edge.  Max visual travel is 44 px.
  static const _kThreshold = 28.0;
  static const _kMaxDrag = 44.0;

  void _reset() {
    if (_dragX == 0 && !_triggered) return;
    setState(() {
      _dragX = 0;
      _triggered = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = (_dragX / _kThreshold).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) {
        if (widget.onReply == null) return;
        if (d.delta.dx < 0 && _dragX <= 0) return;
        final nx = (_dragX + d.delta.dx).clamp(0.0, _kMaxDrag);
        setState(() => _dragX = nx);
        if (!_triggered && _dragX >= _kThreshold) {
          _triggered = true;
          HapticFeedback.selectionClick();
          widget.onReply?.call();
        }
      },
      onHorizontalDragEnd: (_) => _reset(),
      onHorizontalDragCancel: _reset,
      child: Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          Opacity(
            opacity: t,
            child: const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.reply_rounded, size: 18, color: Colors.white54),
            ),
          ),
          Transform.translate(
            offset: Offset(_dragX, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

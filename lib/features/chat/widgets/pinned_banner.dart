part of '../../../screens/chat/chat_thread_screen.dart';

class _PinnedBanner extends StatelessWidget {
  const _PinnedBanner({
    required this.text,
    required this.onTap,
    required this.onDismiss,
  });

  final String text;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1420),
          border: Border(
            bottom: BorderSide(color: Colors.white.withAlpha(14)),
            left: const BorderSide(color: Color(0xFF7C7AFF), width: 3),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.push_pin_rounded,
                size: 14, color: Color(0xFF7C7AFF)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: Colors.white.withAlpha(200),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: onDismiss,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Icon(Icons.close_rounded,
                    size: 16, color: Colors.white.withAlpha(120)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

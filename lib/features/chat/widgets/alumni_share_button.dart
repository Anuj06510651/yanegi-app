part of '../../../screens/chat/chat_thread_screen.dart';

class _AlumniShareButton extends StatefulWidget {
  const _AlumniShareButton({
    required this.eventId,
    required this.chatId,
  });
  final String eventId;
  final String chatId;

  @override
  State<_AlumniShareButton> createState() => _AlumniShareButtonState();
}

class _AlumniShareButtonState extends State<_AlumniShareButton> {
  String _eventTitle = '';
  String _eventEmoji = '📍';
  String _eventBannerUrl = '';
  String _eventLocation = '';

  @override
  void initState() {
    super.initState();
    _loadEventMeta();
  }

  Future<void> _loadEventMeta() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .get();
      if (!mounted || !doc.exists) return;
      final data = doc.data() ?? {};
      setState(() {
        _eventTitle = (data['title'] ?? '').toString().trim();
        _eventEmoji = (data['eventAvatar'] ?? data['emoji'] ?? data['avatarEmoji'] ?? '📍').toString();
        _eventBannerUrl = (data['bannerUrl'] ?? data['bannerImagePath'] ?? '').toString().trim();
        _eventLocation = (data['locationName'] ?? '').toString().trim();
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Share this event into the alumni chat
        GestureDetector(
          onTap: () => showShareToChatSheet(
            context,
            shareType: 'event_card',
            metadata: {
              'targetId': widget.eventId,
              'title': _eventTitle.isEmpty ? 'Event' : _eventTitle,
              'emoji': _eventEmoji,
              'bannerUrl': _eventBannerUrl,
              'subtitle': _eventLocation,
            },
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2A3A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withAlpha(30)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.share_rounded,
                    size: 13, color: Colors.white.withAlpha(180)),
                const SizedBox(width: 4),
                Text(
                  'Share',
                  style: TextStyle(
                    color: Colors.white.withAlpha(180),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

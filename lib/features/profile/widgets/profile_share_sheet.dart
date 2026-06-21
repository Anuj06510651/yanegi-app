part of '../../../screens/profile_social_screen.dart';

class _ProfileShareSheet extends StatelessWidget {
  const _ProfileShareSheet({
    required this.userId,
    required this.name,
    required this.username,
    required this.avatarUrl,
    required this.profileUrl,
  });

  final String userId;
  final String name;
  final String username;
  final String avatarUrl;
  final String profileUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF101726),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(60),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Share Profile',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          _ShareTile(
            icon: Icons.chat_bubble_rounded,
            label: 'Share in Chat',
            subtitle: 'Send as a card to a DM',
            onTap: () {
              Navigator.pop(context);
              showShareToChatSheet(
                context,
                shareType: 'profile_card',
                metadata: {
                  'targetId': userId,
                  'title': name.isEmpty ? username : name,
                  'subtitle': username,
                  'avatarUrl': avatarUrl,
                  'emoji': '👤',
                },
              );
            },
          ),
          const SizedBox(height: 12),
          _ShareTile(
            icon: Icons.link_rounded,
            label: 'Copy / Share Link',
            subtitle: profileUrl,
            onTap: () async {
              Navigator.pop(context);
              try {
                await Share.share(
                  'Check out this profile on Yanegi: $profileUrl',
                );
              } catch (_) {}
            },
          ),
        ],
      ),
    );
  }
}

class _ShareTile extends StatelessWidget {
  const _ShareTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2535),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: YanegiColors.primary.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: YanegiColors.primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: TextStyle(
                          color: Colors.white.withAlpha(120), fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: Colors.white.withAlpha(80)),
          ],
        ),
      ),
    );
  }
}

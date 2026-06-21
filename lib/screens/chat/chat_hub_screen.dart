import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

import '../../chat/models/chat_models.dart';
import '../../chat/providers/chat_providers.dart';
import '../../providers/explore_feed_provider.dart';
import '../../services/event_service.dart';
import '../../services/friend_service.dart';
import '../../theme/yanegi_theme.dart';
import '../../widgets/app_avatars.dart';
import '../../widgets/app_image_viewer.dart';
import '../event_participants_screen.dart';
import '../profile_social_screen.dart';
import 'chat_thread_screen.dart';

class ChatHubScreen extends ConsumerStatefulWidget {
  const ChatHubScreen({super.key});

  @override
  ConsumerState<ChatHubScreen> createState() => _ChatHubScreenState();
}

class _ChatHubScreenState extends ConsumerState<ChatHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _searchQuery = ValueNotifier<String>('');
  int _activeTabIndex = 0;

  bool get _isDarkTheme => Theme.of(context).brightness == Brightness.dark;
  Color get _bgColor =>
      _isDarkTheme ? const Color(0xFF090D15).withAlpha(240) : Colors.white;
  Color get _surfaceColor =>
      _isDarkTheme ? const Color(0xFF171D2A) : Colors.white;
  Color get _borderColor =>
      _isDarkTheme ? Colors.white.withAlpha(14) : Colors.black.withAlpha(12);
  Color get _textPrimary => _isDarkTheme ? Colors.white : Colors.black87;
  Color get _textSecondary =>
      _isDarkTheme ? Colors.white.withAlpha(150) : Colors.black54;

  String get _searchHintText {
    if (_activeTabIndex == 2) {
      return 'Search people by name or username';
    }
    return 'Search chats';
  }

  void _handleTabChanged() {
    if (!mounted) return;
    final nextIndex = _tabController.index;
    if (nextIndex == _activeTabIndex) return;
    setState(() {
      _activeTabIndex = nextIndex;
    });
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _searchController.dispose();
    _searchQuery.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bgColor,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: _buildTopBar(),
            ),
            SizedBox(
              height: 42,
              child: TabBar(
                controller: _tabController,
                indicatorColor: YanegiColors.primary,
                indicatorWeight: 3,
                isScrollable: true,
                dividerColor: Colors.transparent,
                labelColor: _textPrimary,
                unselectedLabelColor: _textSecondary,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(text: 'DMs'),
                  Tab(text: 'Groups'),
                  Tab(text: 'Discover People'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _DmTab(searchQueryListenable: _searchQuery),
                  _GroupsTab(searchQueryListenable: _searchQuery),
                  _DiscoverPeopleTab(searchQueryListenable: _searchQuery),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: _surfaceColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _borderColor),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => _searchQuery.value = value.trim(),
              style: TextStyle(color: _textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: _searchHintText,
                hintStyle: TextStyle(
                  color: _textSecondary,
                  fontSize: 14,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: _textSecondary,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.only(top: 12, right: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DmTab extends ConsumerWidget {
  final ValueListenable<String> searchQueryListenable;

  const _DmTab({required this.searchQueryListenable});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = ref.watch(currentUserIdProvider);
    final dmsAsync = ref.watch(dmListProvider);

    return dmsAsync.when(
      data: (dms) {
        return ValueListenableBuilder<String>(
          valueListenable: searchQueryListenable,
          builder: (context, query, _) {
            final normalized = query.toLowerCase();
            final filtered = normalized.isEmpty
                ? dms
                : dms.where((dm) {
                    final hay = '${dm.name} ${dm.lastMessage}'.toLowerCase();
                    return hay.contains(normalized);
                  }).toList(growable: false);

            if (filtered.isEmpty) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return Center(
                child: Text(
                  normalized.isEmpty
                      ? 'No conversations yet'
                      : 'No chats found',
                  style: TextStyle(
                    color:
                        isDark ? Colors.white.withAlpha(150) : Colors.black54,
                  ),
                ),
              );
            }

            return ListView.builder(
              key: const PageStorageKey<String>('dm_chat_list'),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 110),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final dm = filtered[index];
                return Column(
                  children: [
                    Dismissible(
                      key: ValueKey('dm_${dm.id}'),
                      direction: DismissDirection.horizontal,
                      background: _swipeActionBackground(
                        alignment: Alignment.centerLeft,
                        color: const Color(0xFF7C7AFF),
                        icon: Icons.push_pin_rounded,
                        label: dm.isPinned ? 'Unpin' : 'Pin',
                      ),
                      secondaryBackground: _swipeActionBackground(
                        alignment: Alignment.centerRight,
                        color: YanegiColors.primary,
                        icon: Icons.delete_outline_rounded,
                        label: 'Delete',
                      ),
                      confirmDismiss: (direction) async {
                        final repo = ref.read(chatRepositoryProvider);
                        if (direction == DismissDirection.startToEnd) {
                          await repo.performDmAction(
                            chatId: dm.id,
                            action: DmSwipeAction.pin,
                          );
                          return false;
                        }
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            backgroundColor: const Color(0xFF101726),
                            title: const Text(
                              'Delete chat?',
                              style: TextStyle(color: Colors.white),
                            ),
                            content: const Text(
                              'This chat will be removed only for you.',
                              style: TextStyle(color: Colors.white70),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(true),
                                child: const Text(
                                  'Delete',
                                  style: TextStyle(color: Colors.redAccent),
                                ),
                              ),
                            ],
                          ),
                        );
                        return confirmed == true;
                      },
                      onDismissed: (direction) async {
                        if (direction != DismissDirection.endToStart) return;
                        final repo = ref.read(chatRepositoryProvider);
                        final messenger = ScaffoldMessenger.of(context);
                        await repo.performDmAction(
                          chatId: dm.id,
                          action: DmSwipeAction.delete,
                        );
                        messenger.showSnackBar(
                          SnackBar(
                            content: const Text('Chat deleted'),
                            duration: const Duration(seconds: 3),
                            action: SnackBarAction(
                              label: 'UNDO',
                              onPressed: () =>
                                  repo.undoDeleteChat(chatId: dm.id),
                            ),
                          ),
                        );
                      },
                      child: _DmTile(
                        dm: dm,
                        currentUserId: currentUserId,
                      ),
                    ),
                    if (index != filtered.length - 1)
                      Divider(
                        height: 1,
                        thickness: 0.8,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white.withAlpha(18)
                            : Colors.black.withAlpha(12),
                        indent: 74,
                      ),
                  ],
                );
              },
            );
          },
        );
      },
      error: (_, index) => Center(
        child: Text(
          'Could not load DMs',
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withAlpha(150)
                : Colors.black54,
          ),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _DmTile extends ConsumerWidget {
  final ChatConversation dm;
  final String currentUserId;

  const _DmTile({required this.dm, required this.currentUserId});

  Future<void> _openChatActions(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF131A27),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  dm.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: Colors.white,
                ),
                title: Text(
                  dm.isPinned ? 'Unpin chat' : 'Pin chat',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await ref.read(chatRepositoryProvider).performDmAction(
                        chatId: dm.id,
                        action: DmSwipeAction.pin,
                      );
                },
              ),
              ListTile(
                leading: Icon(
                  dm.isMuted
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  color: Colors.white,
                ),
                title: Text(
                  dm.isMuted ? 'Unmute chat' : 'Mute chat',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await ref.read(chatRepositoryProvider).performDmAction(
                        chatId: dm.id,
                        action: DmSwipeAction.mute,
                      );
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Delete chat',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      backgroundColor: const Color(0xFF101726),
                      title: const Text(
                        'Delete chat?',
                        style: TextStyle(color: Colors.white),
                      ),
                      content: const Text(
                        'This chat will be removed only for you.',
                        style: TextStyle(color: Colors.white70),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          child: const Text(
                            'Delete',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  final repo = ref.read(chatRepositoryProvider);
                  final messenger = ScaffoldMessenger.of(context);
                  await repo.performDmAction(
                    chatId: dm.id,
                    action: DmSwipeAction.delete,
                  );
                  if (context.mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: const Text('Chat deleted'),
                        duration: const Duration(seconds: 3),
                        action: SnackBarAction(
                          label: 'UNDO',
                          onPressed: () =>
                              repo.undoDeleteChat(chatId: dm.id),
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textSecondary = isDark ? Colors.white.withAlpha(170) : Colors.black54;
    return GestureDetector(
      onLongPress: () => _openChatActions(context, ref),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            // Fire-and-forget cursor cache warm — completes during the
            // route-push animation so the thread's `_selfCursorStream`
            // first emit is a cache hit instead of a network roundtrip.
            ref.read(chatRepositoryProvider).prewarmCursor(dm.id);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatThreadScreen(
                  chatId: dm.id,
                  title: dm.name,
                  peerUserId: dm.otherUserId,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
            child: Row(
              children: [
                _ChatAvatar.dm(dm: dm),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              dm.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (dm.isPinned)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Icon(
                                Icons.push_pin_rounded,
                                size: 15,
                                color: Colors.white.withAlpha(165),
                              ),
                            ),
                          if (dm.isMuted)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Icon(
                                Icons.volume_off_rounded,
                                size: 15,
                                color: Colors.white.withAlpha(165),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _dmPreviewText(dm, currentUserId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: dm.isTyping
                              ? const Color(0xFF22E7A2)
                              : textSecondary,
                          fontSize: 13,
                          fontStyle:
                              dm.isTyping ? FontStyle.italic : FontStyle.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _RightMetaSection(
                  timeLabel: _formatChatListTime(dm.updatedAt),
                  unreadCount: dm.isMuted ? 0 : dm.unreadCount,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _swipeActionBackground({
  required Alignment alignment,
  required Color color,
  required IconData icon,
  required String label,
}) {
  return Container(
    alignment: alignment,
    margin: const EdgeInsets.symmetric(vertical: 4),
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: BoxDecoration(
      color: color.withAlpha(220),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: alignment == Alignment.centerLeft
          ? [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ]
          : [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, color: Colors.white),
            ],
    ),
  );
}

class _GroupsTab extends ConsumerWidget {
  final ValueListenable<String> searchQueryListenable;

  const _GroupsTab({required this.searchQueryListenable});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = ref.watch(currentUserIdProvider);
    final groupsAsync = ref.watch(groupListProvider);

    return groupsAsync.when(
      data: (groups) {
        return ValueListenableBuilder<String>(
          valueListenable: searchQueryListenable,
          builder: (context, query, _) {
            final normalized = query.toLowerCase();
            final filtered = normalized.isEmpty
                ? groups
                : groups.where((group) {
                    final hay =
                        '${group.name} ${group.lastMessage}'.toLowerCase();
                    return hay.contains(normalized);
                  }).toList(growable: false);

            if (filtered.isEmpty) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return Center(
                child: Text(
                  normalized.isEmpty ? 'No event chats yet' : 'No chats found',
                  style: TextStyle(
                    color:
                        isDark ? Colors.white.withAlpha(150) : Colors.black54,
                  ),
                ),
              );
            }

            return ListView.builder(
              key: const PageStorageKey<String>('group_chat_list'),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 110),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final g = filtered[index];
                return Column(
                  children: [
                    _GroupTile(
                      key: ValueKey('group_${g.id}'),
                      group: g,
                      currentUserId: currentUserId,
                    ),
                    if (index != filtered.length - 1)
                      Divider(
                        height: 1,
                        thickness: 0.8,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white.withAlpha(18)
                            : Colors.black.withAlpha(12),
                        indent: 74,
                      ),
                  ],
                );
              },
            );
          },
        );
      },
      error: (_, index) => Center(
        child: Text(
          'Could not load groups',
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withAlpha(150)
                : Colors.black54,
          ),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _GroupTile extends ConsumerWidget {
  final EventService _eventService = EventService();
  final ChatGroup group;
  final String currentUserId;

  _GroupTile({
    super.key,
    required this.group,
    required this.currentUserId,
  });

  /// Returns false (and shows an info dialog) when the current user is an
  /// active participant of an ongoing event group — those chats cannot be
  /// self-deleted while the event is still running.
  Future<bool> _canDelete(BuildContext context) async {
    if (group.eventId.isEmpty || group.isExpiredEventGroup) return true;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('event_participants')
          .doc(group.eventId)
          .collection('users')
          .doc(currentUserId)
          .get();
      if (!doc.exists) return true;
      final status = (doc.data()?['status'] as String?) ?? '';
      if (status == 'active' || status == 'joined') {
        if (context.mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF101726),
              title: const Text(
                'Cannot delete chat',
                style: TextStyle(color: Colors.white),
              ),
              content: const Text(
                "This chat remains available while you're participating in this event.",
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return false;
      }
    } catch (_) {}
    return true;
  }

  Future<bool> _confirmAction({
    required BuildContext context,
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    bool destructive = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF101726),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              confirmLabel,
              style: TextStyle(
                color: destructive ? Colors.redAccent : null,
              ),
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _openGroupActions(BuildContext context, WidgetRef ref) async {
    final isHost = currentUserId.isNotEmpty &&
        group.hostId.isNotEmpty &&
        currentUserId == group.hostId;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF131A27),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final repo = ref.read(chatRepositoryProvider);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  group.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: Colors.white,
                ),
                title: Text(
                  group.isPinned ? 'Unpin chat' : 'Pin chat',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await repo.performGroupAction(
                    chatId: group.id,
                    action: DmSwipeAction.pin,
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  group.isMuted
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  color: Colors.white,
                ),
                title: Text(
                  group.isMuted ? 'Unmute chat' : 'Mute chat',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await repo.performGroupAction(
                    chatId: group.id,
                    action: DmSwipeAction.mute,
                  );
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Delete chat',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  if (!await _canDelete(context)) return;
                  final confirmed = await _confirmAction(
                    context: context,
                    title: 'Delete chat?',
                    message:
                        'This chat will be removed only for you. You can rejoin later if needed.',
                    confirmLabel: 'Delete',
                    destructive: true,
                  );
                  if (!confirmed) return;
                  final messenger = ScaffoldMessenger.of(context);
                  await repo.performGroupAction(
                    chatId: group.id,
                    action: DmSwipeAction.delete,
                  );
                  if (context.mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: const Text('Chat deleted'),
                        duration: const Duration(seconds: 3),
                        action: SnackBarAction(
                          label: 'UNDO',
                          onPressed: () => ref
                              .read(chatRepositoryProvider)
                              .undoDeleteChat(chatId: group.id),
                        ),
                      ),
                    );
                  }
                },
              ),
              if (!isHost)
                ListTile(
                  leading: const Icon(Icons.exit_to_app_rounded,
                      color: Colors.white),
                  title: const Text(
                    'Leave Group',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    final confirmed = await _confirmAction(
                      context: context,
                      title: 'Leave group?',
                      message:
                          'You will stop receiving messages from this event group.',
                      confirmLabel: 'Leave',
                      destructive: true,
                    );
                    if (!confirmed) return;
                    await repo.leaveGroupChat(
                      chatId: group.id,
                      eventId: group.eventId,
                    );
                  },
                ),
              if (isHost)
                ListTile(
                  leading:
                      const Icon(Icons.group_outlined, color: Colors.white),
                  title: const Text(
                    'View Participants',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EventParticipantsScreen(
                          eventId: group.eventId,
                          hostId: group.hostId,
                          currentUserId: currentUserId,
                        ),
                      ),
                    );
                  },
                ),
              if (isHost)
                ListTile(
                  leading: const Icon(
                    Icons.person_remove_alt_1_outlined,
                    color: Colors.white,
                  ),
                  title: const Text(
                    'Remove User',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EventParticipantsScreen(
                          eventId: group.eventId,
                          hostId: group.hostId,
                          currentUserId: currentUserId,
                        ),
                      ),
                    );
                  },
                ),
              if (isHost)
                ListTile(
                  leading: const Icon(
                    Icons.event_busy_outlined,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    'Delete Event',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    final confirmed = await _confirmAction(
                      context: context,
                      title: 'Delete event?',
                      message:
                          'Host cannot leave the group. Deleting event will end this group chat for everyone.',
                      confirmLabel: 'Delete Event',
                      destructive: true,
                    );
                    if (!confirmed) return;
                    await _eventService.softDeleteEvent(
                      eventId: group.eventId,
                      hostId: currentUserId,
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textSecondary = isDark ? Colors.white.withAlpha(170) : Colors.black54;
    return Dismissible(
      key: ValueKey('group_swipe_${group.id}'),
      direction: DismissDirection.horizontal,
      background: _swipeActionBackground(
        alignment: Alignment.centerLeft,
        color: const Color(0xFF7C7AFF),
        icon: Icons.push_pin_rounded,
        label: group.isPinned ? 'Unpin' : 'Pin',
      ),
      secondaryBackground: _swipeActionBackground(
        alignment: Alignment.centerRight,
        color: YanegiColors.primary,
        icon: Icons.delete_outline_rounded,
        label: 'Delete',
      ),
      confirmDismiss: (direction) async {
        final repo = ref.read(chatRepositoryProvider);
        if (direction == DismissDirection.startToEnd) {
          await repo.performGroupAction(
            chatId: group.id,
            action: DmSwipeAction.pin,
          );
          return false;
        }
        if (!await _canDelete(context)) return false;
        final confirmed = await _confirmAction(
          context: context,
          title: 'Delete chat?',
          message:
              'This chat will be removed only for you. You can rejoin later if needed.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        return confirmed;
      },
      onDismissed: (direction) async {
        if (direction != DismissDirection.endToStart) return;
        final repo = ref.read(chatRepositoryProvider);
        final messenger = ScaffoldMessenger.of(context);
        await repo.performGroupAction(
          chatId: group.id,
          action: DmSwipeAction.delete,
        );
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Chat deleted'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'UNDO',
              onPressed: () => repo.undoDeleteChat(chatId: group.id),
            ),
          ),
        );
      },
      child: GestureDetector(
        onLongPress: () => _openGroupActions(context, ref),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              ref.read(chatRepositoryProvider).prewarmCursor(group.id);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatThreadScreen(
                    chatId: group.id,
                    title: group.name,
                    isGroup: true,
                    eventId: group.eventId,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
              child: Row(
                children: [
                  _ChatAvatar.group(group: group),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                group.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (group.isPinned)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(
                                  Icons.push_pin_rounded,
                                  size: 15,
                                  color: textSecondary,
                                ),
                              ),
                            if (group.isMuted)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(
                                  Icons.volume_off_rounded,
                                  size: 15,
                                  color: textSecondary,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _groupPreviewText(group, currentUserId),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _RightMetaSection(
                    timeLabel: _formatChatListTime(group.updatedAt),
                    unreadCount: 0,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatAvatar extends StatelessWidget {
  final String? imageUrl;
  final String fallbackText;
  final bool showRoundedBanner;
  final bool showIconFallback;
  final String? eventAvatar;

  const _ChatAvatar._({
    required this.imageUrl,
    required this.fallbackText,
    required this.showRoundedBanner,
    required this.showIconFallback,
    this.eventAvatar,
  });

  factory _ChatAvatar.dm({required ChatConversation dm}) {
    return _ChatAvatar._(
      imageUrl: dm.avatarUrl.trim().isEmpty ? null : dm.avatarUrl.trim(),
      fallbackText: dm.avatarEmoji,
      showRoundedBanner: false,
      showIconFallback: true,
    );
  }

  factory _ChatAvatar.group({required ChatGroup group}) {
    final banner = group.resolvedBannerUrl;
    final avatar = group.resolvedEventAvatar;

    return _ChatAvatar._(
      imageUrl: banner.isEmpty ? null : banner,
      fallbackText: '',
      showRoundedBanner: banner.isNotEmpty,
      showIconFallback: true,
      eventAvatar: avatar.isEmpty ? null : avatar,
    );
  }

  @override
  Widget build(BuildContext context) {
    // DM rows use the branded person avatar.
    if (!showRoundedBanner && fallbackText.isNotEmpty) {
      return AppUserAvatar(photoUrl: imageUrl, radius: 24);
    }
    // Group rows use EventCategoryAvatar which knows how to render
    // banner photos, asset icons, and emoji — all with consistent fallbacks.
    return EventCategoryAvatar(
      bannerUrl: imageUrl,
      eventAvatar: eventAvatar,
      radius: 24,
    );
  }
}

class _RightMetaSection extends StatelessWidget {
  final String timeLabel;
  final int unreadCount;

  const _RightMetaSection({required this.timeLabel, required this.unreadCount});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 56,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            timeLabel,
            style: TextStyle(
              color: isDark ? Colors.white.withAlpha(145) : Colors.black45,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          if (unreadCount > 0)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: YanegiColors.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                unreadCount > 99 ? '99+' : unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            const SizedBox(height: 22),
        ],
      ),
    );
  }
}

String _dmPreviewText(ChatConversation dm, String currentUserId) {
  if (dm.isTyping) return 'Typing…';
  final message = dm.lastMessage.trim();
  if (message.isEmpty) return 'No messages yet';

  final senderId = dm.lastMessageSenderId.trim();
  final senderName = dm.lastMessageSenderName.trim();

  if (senderId.isEmpty && senderName.isEmpty) return message;
  if (senderId == currentUserId) return 'you: $message';
  final label = senderName.isNotEmpty ? senderName : dm.name;
  return '$label: $message';
}

String _groupPreviewText(ChatGroup group, String currentUserId) {
  final message = group.lastMessage.trim();
  if (message.isEmpty) return 'No messages yet';

  final senderId = group.lastMessageSenderId.trim();
  final senderName = group.lastMessageSenderName.trim();

  if (senderId.isEmpty && senderName.isEmpty) return message;
  if (senderId == currentUserId) return 'you: $message';
  final label = senderName.isNotEmpty ? senderName : 'Member';
  return '$label: $message';
}

String _formatChatListTime(DateTime dateTime) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(dateTime.year, dateTime.month, dateTime.day);
  final dayDiff = today.difference(date).inDays;

  if (dayDiff <= 0) return DateFormat('h:mm a').format(dateTime);
  if (dayDiff == 1) return 'Yesterday';
  return DateFormat('MMM d').format(dateTime);
}

class _DiscoverPeopleTab extends ConsumerStatefulWidget {
  final ValueListenable<String> searchQueryListenable;

  const _DiscoverPeopleTab({required this.searchQueryListenable});

  @override
  ConsumerState<_DiscoverPeopleTab> createState() => _DiscoverPeopleTabState();
}

class _DiscoverPeopleTabState extends ConsumerState<_DiscoverPeopleTab> {
  final FriendService _friendService = FriendService();
  final Set<String> _requestInFlightIds = <String>{};
  // Dismissed card IDs — cleared on full refresh.
  final Set<String> _dismissedIds = <String>{};

  String _usernameText(DiscoverPerson p) {
    final provided = p.username.trim().toLowerCase();
    if (provided.isNotEmpty) {
      return provided.startsWith('@') ? provided : '@$provided';
    }
    final base = p.name.trim().toLowerCase();
    if (base.isEmpty) return '@user';
    final compact = base.replaceAll(RegExp(r'\s+'), '');
    return compact.startsWith('@') ? compact : '@$compact';
  }

  Future<void> _openAvatarViewer(
    BuildContext context,
    DiscoverPerson p,
  ) async {
    final imageUrl = (p.avatarUrl ?? '').trim();
    if (imageUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No profile image available.')),
      );
      return;
    }

    await AppImageViewer.open(
      context,
      imageUrl: imageUrl,
      isCircular: true,
    );
  }

  Future<void> _openProfile(BuildContext context, DiscoverPerson p) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SocialProfileScreen(profileUserId: p.id),
      ),
    );
  }

  Widget _buildPrimarySuggestionContext(DiscoverPerson p) {
    if (p.mutualFriendsCount > 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            _MutualAvatarStack(avatarUrls: p.mutualFriendAvatarUrls),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${p.mutualFriendsCount} mutual friend${p.mutualFriendsCount == 1 ? '' : 's'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: YanegiColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (p.isNearby) {
      return const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_on_rounded,
              size: 13,
              color: YanegiColors.primary,
            ),
            SizedBox(width: 4),
            Text(
              'Nearby you',
              style: TextStyle(
                color: YanegiColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    if ((p.suggestionLabel ?? '').trim().isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          p.suggestionLabel!,
          style: TextStyle(
            color: Colors.white.withAlpha(145),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Future<void> _sendRequest(DiscoverPerson person) async {
    if (_requestInFlightIds.contains(person.id)) return;

    setState(() => _requestInFlightIds.add(person.id));
    final success = await _friendService.sendFriendRequest(person.id);
    print('Friend request success: $success');

    if (!mounted) return;

    if (success) {
      ref.invalidate(discoverFriendshipStateProvider(person.id));
      ref.invalidate(discoverPeopleProvider);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send friend request.')),
      );
    }

    if (mounted) {
      setState(() => _requestInFlightIds.remove(person.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final peopleAsync = ref.watch(discoverPeopleProvider);

    return peopleAsync.when(
      loading: () => _buildSkeletonList(isDark),
      error: (_, __) => _buildErrorState(isDark),
      data: (people) {
        return ValueListenableBuilder<String>(
          valueListenable: widget.searchQueryListenable,
          builder: (context, query, _) {
            final normalized = query.trim().toLowerCase();

            // Apply dismiss + search filters.
            final visible = people.where((p) => !_dismissedIds.contains(p.id)).toList();
            final filtered = normalized.isEmpty
                ? visible
                : visible.where((p) {
                    final name = p.name.toLowerCase();
                    final username = p.username.toLowerCase();
                    final vibes = p.commonVibes.join(' ').toLowerCase();
                    return name.contains(normalized) ||
                        username.contains(normalized) ||
                        vibes.contains(normalized);
                  }).toList(growable: false);

            // The never-empty guarantee is in the algorithm layer.
            // This empty state is a true last-resort (e.g. brand-new app, 0 users).
            if (people.isEmpty) {
              return _buildEmptyState(isDark);
            }

            if (filtered.isEmpty && normalized.isNotEmpty) {
              return Center(
                child: Text(
                  'No people found for "$normalized"',
                  style: TextStyle(
                    color: isDark ? Colors.white.withAlpha(150) : Colors.black54,
                  ),
                ),
              );
            }

            if (filtered.isEmpty) {
              // All cards dismissed — show a refresh nudge.
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'You\'ve seen everyone for now',
                      style: TextStyle(
                        color: isDark ? Colors.white.withAlpha(170) : Colors.black87,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        setState(() => _dismissedIds.clear());
                        ref.invalidate(discoverPeopleProvider);
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Refresh suggestions'),
                      style: TextButton.styleFrom(
                        foregroundColor: YanegiColors.primary,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 110),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final p = filtered[index];
                final liveRelationAsync =
                    ref.watch(discoverFriendshipStateProvider(p.id));
                final relationStatus =
                    liveRelationAsync.valueOrNull ?? FriendRelationStatus.add;
                final isSending = _requestInFlightIds.contains(p.id);
                final isVibeMatch = p.commonVibes.isNotEmpty;

                return AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: 1.0,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF131A27) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isVibeMatch
                            ? YanegiColors.primary.withAlpha(60)
                            : isDark
                                ? Colors.white.withAlpha(10)
                                : Colors.black.withAlpha(12),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Material(
                              color: Colors.transparent,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => _openAvatarViewer(context, p),
                                child: AppUserAvatar(
                                  photoUrl: p.avatarUrl,
                                  radius: 23,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => _openProfile(context, p),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 2, horizontal: 2),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.name,
                                          style: TextStyle(
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black87,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          _usernameText(p),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isDark
                                                ? Colors.white.withAlpha(165)
                                                : Colors.black54,
                                            fontSize: 12,
                                          ),
                                        ),
                                        _buildPrimarySuggestionContext(p),
                                        if (p.detail.isNotEmpty)
                                          Text(
                                            p.detail,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: isDark
                                                  ? Colors.white.withAlpha(140)
                                                  : Colors.black54,
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Dismiss button
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _dismissedIds.add(p.id)),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 6, top: 2),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: isDark
                                      ? Colors.white.withAlpha(80)
                                      : Colors.black38,
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Vibe chips row
                        if (p.commonVibes.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildVibeChips(p.commonVibes, isDark),
                        ],
                        // Action row
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            if (p.seenAtSameEvent)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF22E7A2).withAlpha(28),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  '✓ Same event',
                                  style: TextStyle(
                                    color: Color(0xFF22E7A2),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            const Spacer(),
                            SizedBox(
                              height: 34,
                              child: ElevatedButton(
                                onPressed:
                                    relationStatus == FriendRelationStatus.add &&
                                            !isSending
                                        ? () => _sendRequest(p)
                                        : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      relationStatus == FriendRelationStatus.friends
                                          ? const Color(0xFF2D3748)
                                          : YanegiColors.primary,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 14),
                                ),
                                child: Text(
                                  relationStatus == FriendRelationStatus.friends
                                      ? 'Friends'
                                      : relationStatus ==
                                              FriendRelationStatus.requested
                                          ? 'Requested'
                                          : (isSending ? 'Sending…' : 'Add Friend'),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSkeletonList(bool isDark) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 110),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => _DiscoverSkeleton(isDark: isDark),
    );
  }

  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded,
              size: 40, color: isDark ? Colors.white38 : Colors.black26),
          const SizedBox(height: 12),
          Text(
            'Could not load people',
            style: TextStyle(
              color: isDark ? Colors.white.withAlpha(150) : Colors.black54,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => ref.invalidate(discoverPeopleProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
            style: TextButton.styleFrom(foregroundColor: YanegiColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🌍', style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            'Be the first to explore',
            style: TextStyle(
              color: isDark ? Colors.white.withAlpha(200) : Colors.black87,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Join events to meet people with your vibe',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white.withAlpha(110) : Colors.black54,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              // Switch to the Explore tab in the main nav.
              ref.read(activeTabProvider.notifier).state = HomeTab.explore;
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            icon: const Icon(Icons.explore_rounded, size: 18),
            label: const Text('Explore events'),
            style: ElevatedButton.styleFrom(
              backgroundColor: YanegiColors.primary,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVibeChips(List<String> vibes, bool isDark) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: vibes.take(4).map((vibe) {
        final label = vibe.isEmpty
            ? vibe
            : vibe[0].toUpperCase() + vibe.substring(1);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: YanegiColors.primary.withAlpha(22),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: YanegiColors.primary.withAlpha(60),
              width: 1,
            ),
          ),
          child: Text(
            '✨ $label',
            style: TextStyle(
              color: YanegiColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _MutualAvatarStack extends StatelessWidget {
  final List<String> avatarUrls;

  const _MutualAvatarStack({required this.avatarUrls});

  @override
  Widget build(BuildContext context) {
    final visible =
        avatarUrls.where((url) => url.trim().isNotEmpty).take(3).toList();
    final count = visible.isEmpty ? 2 : visible.length;

    return SizedBox(
      width: 14 + ((count - 1) * 10),
      height: 14,
      child: Stack(
        clipBehavior: Clip.none,
        children: List.generate(count, (index) {
          final hasUrl = index < visible.length;
          final url = hasUrl ? visible[index] : '';
          return Positioned(
            left: index * 10,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF131A27), width: 1.4),
                color: const Color(0xFF2B3444),
              ),
              child: ClipOval(
                child: hasUrl
                    ? CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        memCacheWidth: 42,
                        memCacheHeight: 42,
                        errorWidget: (context, _, __) => const Icon(
                          Icons.person_rounded,
                          size: 10,
                          color: Colors.white70,
                        ),
                      )
                    : const Icon(
                        Icons.person_rounded,
                        size: 10,
                        color: Colors.white70,
                      ),
              ),
            ),
          );
        }),
      ),
    );
  }
}


class _DiscoverSkeleton extends StatelessWidget {
  const _DiscoverSkeleton({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final base = isDark ? const Color(0xFF1E2A3A) : const Color(0xFFE8EDF2);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131A27) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withAlpha(10)
              : Colors.black.withAlpha(12),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(shape: BoxShape.circle, color: base),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 12,
                  width: 120,
                  decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(6)),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 10,
                  width: 80,
                  decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(6)),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 10,
                  width: 160,
                  decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(6)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 80,
            height: 32,
            decoration: BoxDecoration(
                color: base, borderRadius: BorderRadius.circular(8)),
          ),
        ],
      ),
    );
  }
}

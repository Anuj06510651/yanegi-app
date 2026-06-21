// ignore_for_file: invalid_use_of_protected_member

part of '../../../screens/chat/chat_thread_screen.dart';

extension _ChatMentionController on _ChatThreadScreenState {
  Future<void> _loadParticipantNames(List<String> uids) async {
    if (uids.isEmpty) return;
    final currentUserId = ref.read(currentUserIdProvider);
    final toFetch = uids
        .where((id) => id != currentUserId && !_participantNames.containsKey(id))
        .toList();
    if (toFetch.isEmpty) return;

    const chunkSize = 10;
    for (var i = 0; i < toFetch.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, toFetch.length);
      final chunk = toFetch.sublist(i, end);
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          final d = doc.data();
          // Prefer username (no spaces → easier mention matching) then name.
          final name = ((d['username'] ?? d['name'] ?? '') as String).trim();
          if (name.isNotEmpty && mounted) {
            _participantNames[doc.id] = name;
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  void _detectMentionQuery(String text) {
    if (!widget.isGroup) return;
    final cursor = _textController.selection.isValid
        ? _textController.selection.baseOffset
        : text.length;
    if (cursor <= 0) {
      _clearMentionSuggestions();
      return;
    }
    final sub = text.substring(0, cursor);
    final atIdx = sub.lastIndexOf('@');
    if (atIdx == -1) {
      _clearMentionSuggestions();
      return;
    }
    // If there's a whitespace between @ and cursor, no active mention query.
    final between = sub.substring(atIdx + 1);
    if (between.contains(' ') || between.contains('\n')) {
      _clearMentionSuggestions();
      return;
    }
    final query = between.toLowerCase();
    _mentionAnchorIndex = atIdx;

    final currentUid = ref.read(currentUserIdProvider);
    final suggestions = _participantNames.entries
        .where((e) {
          if (e.key == currentUid) return false;
          final nameLower = e.value.toLowerCase();
          return query.isEmpty ||
              nameLower.startsWith(query) ||
              nameLower.contains(query);
        })
        .take(6)
        .toList();

    if (mounted) setState(() => _mentionSuggestions = suggestions);
  }

  void _clearMentionSuggestions() {
    if (_mentionSuggestions.isEmpty && _mentionAnchorIndex == -1) return;
    if (mounted) {
      setState(() {
        _mentionSuggestions = [];
        _mentionAnchorIndex = -1;
      });
    }
  }

  void _applyMention(String uid, String name) {
    final text = _textController.text;
    final cursor = _textController.selection.isValid
        ? _textController.selection.baseOffset
        : text.length;
    final prefix = _mentionAnchorIndex >= 0 && _mentionAnchorIndex < text.length
        ? text.substring(0, _mentionAnchorIndex)
        : '';
    final suffix = cursor < text.length ? text.substring(cursor) : '';
    final insertion = '@$name ';
    final newText = '$prefix$insertion$suffix';
    _textController.value = TextEditingValue(
      text: newText,
      selection:
          TextSelection.collapsed(offset: prefix.length + insertion.length),
    );
    setState(() {
      _mentionSuggestions = [];
      _mentionAnchorIndex = -1;
    });
  }

  Widget _buildMentionSuggestionsBar() {
    if (_mentionSuggestions.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF0B1019),
        border: Border(
          top: BorderSide(color: Colors.white.withAlpha(12)),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        itemCount: _mentionSuggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final entry = _mentionSuggestions[i];
          return GestureDetector(
            onTap: () => _applyMention(entry.key, entry.value),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF171D2A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFF7C7AFF).withAlpha(100)),
              ),
              child: Text(
                '@${entry.value}',
                style: const TextStyle(
                  color: Color(0xFF7C7AFF),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _dispatchMentionNotifications(String text) async {
    if (!widget.isGroup || _participantNames.isEmpty) return;
    final mentionPattern = RegExp(r'@(\S+)');
    final mentionedTokens = mentionPattern
        .allMatches(text)
        .map((m) => m.group(1)!.toLowerCase())
        .toSet();
    if (mentionedTokens.isEmpty) return;

    final currentUid = ref.read(currentUserIdProvider);
    final mentionedUids = _participantNames.entries
        .where((e) {
          if (e.key == currentUid) return false;
          final nameLower = e.value.toLowerCase();
          return mentionedTokens.contains(nameLower);
        })
        .map((e) => e.key)
        .toSet();
    if (mentionedUids.isEmpty) return;

    final svc = ActivityNotificationService();
    for (final uid in mentionedUids) {
      try {
        await svc.createNotification(
          receiverId: uid,
          type: NotificationType.mention,
          message: 'mentioned you in ${widget.title}',
          title: 'mentioned you in ${widget.title}',
          chatId: widget.chatId,
          dedupeKey:
              'mention:${widget.chatId}:$uid:${DateTime.now().millisecondsSinceEpoch ~/ 5000}',
          dedupeWindow: const Duration(seconds: 5),
        );
      } catch (_) {}
    }
  }
}

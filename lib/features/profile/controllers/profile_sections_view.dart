// ignore_for_file: invalid_use_of_protected_member

part of '../../../screens/profile_social_screen.dart';

/// View builders for the redesigned profile: identity block, interest tags,
/// member-since, the state-specific connection card (stranger "Why you should
/// connect" / friend "Connection"), the friends strip, the single "Hosting Now"
/// featured card, and the Hosting/Joined events tabs.
extension _ProfileSectionsView on _SocialProfileScreenState {
  // ─── INSTAGRAM-STYLE HEADER (avatar left, stats right, name below) ───
  Widget _buildHingeHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row: avatar on left, stats on right
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildHeaderAvatar(),
              const SizedBox(width: 18),
              Expanded(child: _buildStatsRow()),
            ],
          ),
          const SizedBox(height: 12),
          // Display name below
          Text(
            _displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _textPrimaryColor,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderAvatar() {
    final url = _profileImageUrl.trim();
    final hasImage = url.isNotEmpty && isRemoteMediaUrl(url);

    return GestureDetector(
      onTap: _handleAvatarTap,
      onLongPress: (_isOwnProfile && hasImage)
          ? () => _showMediaOptionsSheet(isBanner: false)
          : null,
      child: Stack(
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: YanegiColors.primary, width: 2.5),
              color: _surfaceColor,
              image: hasImage
                  ? DecorationImage(
                      image: CachedNetworkImageProvider(url),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: hasImage
                ? null
                : Center(
                    child: Text(
                      StaticProfileMediaHeader._initialsFrom(
                          _displayName, _username),
                      style: TextStyle(
                        color: _textPrimaryColor,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
          if (_isOwnProfile)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: YanegiColors.primary,
                  border: Border.all(color: _bgColor, width: 2),
                ),
                child: Icon(
                  hasImage ? Icons.edit : Icons.add,
                  color: Colors.white,
                  size: 13,
                ),
              ),
            ),
          if (_isUploadingMedia && _isInProgress(_profileUploadState))
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withAlpha(90),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _buildStatCell(_friendsTotalCount.toString(), 'Friends',
            onTap: _openFriendsList),
        _buildStatCell(_joinedEvents.length.toString(), 'Joined',
            onTap: () => setState(() => _eventsTabIndex = 1)),
        _buildStatCell(_hostedEvents.length.toString(), 'Hosted',
            onTap: () => setState(() => _eventsTabIndex = 0)),
      ],
    );
  }

  Widget _buildStatCell(String value, String label,
      {VoidCallback? onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: TextStyle(
                color: _textPrimaryColor,
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: _textSecondaryColor.withAlpha(200),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── IDENTITY (name + verified + username) ────────────────
  Widget _buildIdentitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                _displayName,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _textPrimaryColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (_isVerified) ...[
              const SizedBox(width: 6),
              Icon(Icons.verified_rounded,
                  color: YanegiColors.primary.withAlpha(230), size: 18),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          _username,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _textSecondaryColor.withAlpha(210),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ─── INTEREST TAGS ────────────────────────────────────────
  Widget _buildInterestTagsSection() {
    if (_interestTags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        alignment: WrapAlignment.start,
        spacing: 8,
        runSpacing: 8,
        children: _interestTags.map(_buildTagChip).toList(),
      ),
    );
  }

  Widget _buildTagChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _surfaceColor.withAlpha(190),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _textSecondaryColor.withAlpha(45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: _textPrimaryColor,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ─── MEMBER SINCE ─────────────────────────────────────────
  Widget _buildMemberSinceSection() {
    final label = _memberSinceLabel;
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Icon(Icons.calendar_today_rounded,
              size: 13, color: _textSecondaryColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: _textSecondaryColor,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ─── CONNECTION CONTEXT CARD (state-specific) ─────────────
  Widget _buildConnectionContextCard() {
    if (_isOwnProfile || _cachedFriendStateStream == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<FriendRelationshipState>(
      stream: _cachedFriendStateStream,
      builder: (context, snapshot) {
        final state = _optimisticFriendState ??
            (snapshot.data ?? FriendRelationshipState.notFriend);
        final card = state == FriendRelationshipState.friend
            ? _buildFriendConnectionCard()
            : _buildWhyConnectCard();
        if (card == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 18),
          child: card,
        );
      },
    );
  }

  Widget? _buildWhyConnectCard() {
    final rows = <Widget>[];

    final mutual = _mutualFriendsCount ?? 0;
    if (mutual > 0) {
      rows.add(_contextRow(
        icon: Icons.people_alt_rounded,
        title: mutual == 1 ? '1 mutual friend' : '$mutual mutual friends',
        subtitle: 'You share friends in common.',
      ));
    }
    if (_interestTags.isNotEmpty) {
      rows.add(_contextRow(
        icon: Icons.calendar_today_rounded,
        title: 'Active in ${_interestTags.first} events',
        subtitle: 'You may enjoy the same kind of events.',
      ));
    }
    if (_hostedEvents.isNotEmpty) {
      rows.add(_contextRow(
        icon: Icons.campaign_rounded,
        title: 'Active host in the community',
        subtitle: 'Hosts public events you can join.',
      ));
    }

    if (rows.isEmpty) return null;

    return _contextCardShell(
      title: 'Why you should connect',
      rows: rows,
    );
  }

  Widget? _buildFriendConnectionCard() {
    final rows = <Widget>[];

    final since = _memberSince; // best-effort; friendship date not separately stored
    if (since != null) {
      rows.add(_contextRow(
        icon: Icons.handshake_rounded,
        title: 'Connected on Yanegi',
        subtitle: 'You are friends.',
      ));
    }
    final mutual = _mutualFriendsCount ?? 0;
    if (mutual > 0) {
      rows.add(_contextRow(
        icon: Icons.people_alt_rounded,
        title: mutual == 1 ? '1 mutual friend' : '$mutual mutual friends',
        subtitle: 'Friends you both know.',
      ));
    }
    final shared = _sharedEventsCount ?? 0;
    if (shared > 0) {
      rows.add(_contextRow(
        icon: Icons.event_available_rounded,
        title: shared == 1 ? '1 shared event' : '$shared shared events',
        subtitle: 'Events you both attended.',
      ));
    }

    if (rows.isEmpty) return null;
    return _contextCardShell(title: 'Connection', rows: rows);
  }

  Widget _contextCardShell({required String title, required List<Widget> rows}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _textSecondaryColor.withAlpha(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: _textPrimaryColor,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          ...rows,
        ],
      ),
    );
  }

  Widget _contextRow({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: YanegiColors.primary.withAlpha(220)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _textPrimaryColor,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(
                      color: _textSecondaryColor, fontSize: 12, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── FRIENDS STRIP ────────────────────────────────────────
  Widget _buildFriendsStrip() {
    if (_friendsTotalCount == 0 && _friendsPreview.isEmpty) {
      return const SizedBox.shrink();
    }

    final mutualCount = _mutualFriendIds.length;
    final countLabel = (!_isOwnProfile && mutualCount > 0)
        ? (mutualCount == 1 ? '1 Mutual Friend' : '$mutualCount Mutual Friends')
        : (_friendsTotalCount == 1 ? '1 Friend' : '$_friendsTotalCount Friends');

    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Friends',
            style: TextStyle(
              color: _textPrimaryColor,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 56,
            child: Row(
              children: [
                Expanded(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _friendsPreview.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final friend = _friendsPreview[index];
                      return _buildFriendAvatar(friend);
                    },
                  ),
                ),
                if (_friendsTotalCount > _friendsPreview.length) ...[
                  const SizedBox(width: 10),
                  _buildFriendsOverflowChip(
                    _friendsTotalCount - _friendsPreview.length,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                countLabel,
                style: TextStyle(
                  color: YanegiColors.primary.withAlpha(220),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              InkWell(
                onTap: _openFriendsList,
                child: Text(
                  'View All',
                  style: TextStyle(
                    color: YanegiColors.primary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFriendAvatar(UserProfile friend) {
    return InkWell(
      onTap: () => _openProfileById(friend.uid),
      borderRadius: BorderRadius.circular(999),
      child: AppUserAvatar(
        photoUrl: friend.avatarUrl,
        radius: 24,
        showRing: _mutualFriendIds.contains(friend.uid),
      ),
    );
  }

  Widget _buildFriendsOverflowChip(int extra) {
    return InkWell(
      onTap: _openFriendsList,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _surfaceColor,
          border: Border.all(color: _textSecondaryColor.withAlpha(60)),
        ),
        child: Text(
          '+$extra',
          style: TextStyle(
            color: _textPrimaryColor,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<void> _openProfileById(String userId) async {
    if (userId.trim().isEmpty || userId == _profileUid) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SocialProfileScreen(profileUserId: userId),
      ),
    );
  }

  // ─── HOSTING NOW (single featured live event) ─────────────
  Widget _buildHostingNowSection() {
    final live = _liveHostedEvents;
    if (live.isEmpty) return const SizedBox.shrink();

    final doc = live.first;
    final data = doc.data();
    final eventId = doc.id;

    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hosting Now',
            style: TextStyle(
              color: _textPrimaryColor,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => _openHostedEvent(eventId),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 150,
              decoration: BoxDecoration(
                color: _surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _textSecondaryColor.withAlpha(30)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildHostedEventCard(data),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _buildSaveToggle(eventId),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Bookmark toggle backed by the private saved-events store.
  Widget _buildSaveToggle(String eventId) {
    return StreamBuilder<bool>(
      stream: _savedEventsService.isSavedStream(eventId),
      builder: (context, snapshot) {
        final saved = snapshot.data ?? false;
        return Material(
          color: Colors.black.withAlpha(70),
          shape: const CircleBorder(),
          child: IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              color: saved ? YanegiColors.primary : Colors.white,
            ),
            onPressed: () async {
              final nowSaved = await _savedEventsService.toggleSaved(eventId);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(nowSaved ? 'Saved.' : 'Removed from saved.'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ─── EVENTS SECTION (Hosting / Joined tabs) ───────────────
  Widget _buildEventsTabsSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Events',
            style: TextStyle(
              color: _textPrimaryColor,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildEventsTab('Hosting', 0),
              const SizedBox(width: 18),
              _buildEventsTab('Joined', 1),
            ],
          ),
          const SizedBox(height: 12),
          _eventsTabIndex == 0 ? _buildHostingTabBody() : _buildJoinedTabBody(),
        ],
      ),
    );
  }

  Widget _buildEventsTab(String label, int index) {
    final selected = _eventsTabIndex == index;
    return InkWell(
      onTap: () {
        if (_eventsTabIndex == index) return;
        setState(() => _eventsTabIndex = index);
        if (index == 1) _loadJoinedEventsIfNeeded();
      },
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: selected ? YanegiColors.primary : _textSecondaryColor,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 2,
            width: 36,
            color: selected ? YanegiColors.primary : Colors.transparent,
          ),
        ],
      ),
    );
  }

  Widget _buildHostingTabBody() {
    if (_isLoadingHostedEvents && _hostedEvents.isEmpty) {
      return _eventsLoadingRow();
    }
    if (_hostedEvents.isEmpty) {
      return _eventsEmptyText('No hosted events yet.');
    }
    return _buildEventThumbRow(_hostedEvents);
  }

  Widget _buildJoinedTabBody() {
    if (_isLoadingJoinedEvents && _joinedEvents.isEmpty) {
      return _eventsLoadingRow();
    }
    if (_joinedEventsLoaded && _joinedEvents.isEmpty) {
      return _eventsEmptyText('No joined events yet.');
    }
    if (!_joinedEventsLoaded) {
      // First paint of the tab — kick the lazy load.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadJoinedEventsIfNeeded();
      });
      return _eventsLoadingRow();
    }
    return _buildEventThumbRow(_joinedEvents);
  }

  Widget _eventsLoadingRow() {
    return const SizedBox(
      height: 150,
      child: Center(child: CircularProgressIndicator()),
    );
  }

  Widget _eventsEmptyText(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text, style: TextStyle(color: _textSecondaryColor)),
    );
  }

  Widget _buildEventThumbRow(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: docs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final doc = docs[index];
          return _buildEventThumbCard(doc.id, doc.data());
        },
      ),
    );
  }

  Widget _buildEventThumbCard(String eventId, Map<String, dynamic> data) {
    final title = (data['title'] ?? 'Untitled event').toString().trim();
    final dateText = _formatEventDate(data);

    return InkWell(
      onTap: () => _openHostedEvent(eventId),
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 180,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 110,
              width: 180,
              decoration: BoxDecoration(
                color: _surfaceColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _textSecondaryColor.withAlpha(30)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: _buildHostedEventCard(data),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title.isEmpty ? 'Untitled event' : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _textPrimaryColor,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (dateText.isNotEmpty)
              Text(
                dateText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _textSecondaryColor, fontSize: 11.5),
              ),
          ],
        ),
      ),
    );
  }
}

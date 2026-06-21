// ignore_for_file: invalid_use_of_protected_member

part of '../../../screens/profile_social_screen.dart';

extension _FriendActionController on _SocialProfileScreenState {
  Future<void> _openFriendsList() async {
    if (_profileUid.isEmpty) return;

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConnectionsScreen(
          userId: _profileUid,
          initialTab: 'friends',
        ),
      ),
    );
  }

  Future<void> _handlePrimaryAction() async {
    if (_isActionBusy) return;

    if (_isOwnProfile) {
      final didSave = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ProfileEditScreen(
            initialName: _displayName,
            initialUsername: _username,
            initialBio: _bio,
          ),
        ),
      );
      if (didSave == true && mounted) {
        await _loadProfileData();
      }
      return;
    }

    if (!await ActionGate.ensureCanAct(context,
        message: 'Complete your profile to connect with people.')) {
      return;
    }

    setState(() {
      _isActionBusy = true;
      _optimisticFriendState = FriendRelationshipState.requestSent;
    });
    final sent = await _friendService.sendFriendRequest(_profileUid);
    if (!mounted) return;

    setState(() {
      _isActionBusy = false;
      if (!sent) _optimisticFriendState = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(sent ? 'Friend request sent.' : 'Could not send request.')),
    );
  }

  Future<void> _acceptReceivedRequest() async {
    if (_isActionBusy) return;
    if (!await ActionGate.ensureCanAct(context,
        message: 'Complete your profile to connect with people.')) {
      return;
    }
    setState(() {
      _isActionBusy = true;
      _optimisticFriendState = FriendRelationshipState.friend;
    });
    final accepted = await _friendService.acceptFriendRequest(_profileUid);
    if (!mounted) return;
    setState(() {
      _isActionBusy = false;
      if (!accepted) _optimisticFriendState = null;
    });
    if (accepted) unawaited(_loadMutualFriends());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(accepted
              ? 'Friend request accepted.'
              : 'Could not accept request.')),
    );
  }

  Future<void> _declineReceivedRequest() async {
    if (_isActionBusy) return;
    setState(() {
      _isActionBusy = true;
      _optimisticFriendState = FriendRelationshipState.notFriend;
    });
    final declined = await _friendService.declineFriendRequest(_profileUid);
    if (!mounted) return;
    setState(() {
      _isActionBusy = false;
      if (!declined) _optimisticFriendState = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(declined
              ? 'Friend request declined.'
              : 'Could not decline request.')),
    );
  }

  Future<void> _removeCurrentFriend() async {
    if (_isActionBusy) return;

    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: YanegiColors.surface,
          title: const Text(
            'Remove this friend?',
            style: TextStyle(color: YanegiColors.textPrimary),
          ),
          content: const Text(
            'This will remove both of you from each other\'s friends list.',
            style: TextStyle(color: YanegiColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (shouldRemove != true) return;

    setState(() {
      _isActionBusy = true;
      _optimisticFriendState = FriendRelationshipState.notFriend;
    });

    final removed = await _friendService.removeFriend(_profileUid);
    if (!mounted) return;

    setState(() {
      _isActionBusy = false;
      if (!removed) {
        _optimisticFriendState = null;
      }
    });

    if (removed) {
      print('Friend removed');
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(removed ? 'Friend removed.' : 'Could not remove friend.')),
    );
  }

  Future<void> _openDirectMessage() async {
    if (_isActionBusy ||
        _currentUid.trim().isEmpty ||
        _profileUid.trim().isEmpty) {
      return;
    }
    if (!await ActionGate.ensureCanAct(context,
        message: 'Complete your profile to send messages.')) {
      return;
    }

    setState(() => _isActionBusy = true);
    print('Opening DM');

    try {
      final chatId =
          await _chatRepository.createOrGetDM(_currentUid, _profileUid);
      if (!mounted) return;

      if (chatId.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chat unavailable for this user.')),
        );
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatThreadScreen(
            chatId: chatId,
            title: _displayName.isEmpty ? _username : _displayName,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open chat. Please try again.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isActionBusy = false);
      }
    }
  }

  Future<void> _showFriendActionSheet() async {
    if (_isActionBusy) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: YanegiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person_remove_alt_1_rounded,
                    color: Colors.redAccent),
                title: const Text(
                  'Remove Friend',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () => Navigator.of(sheetContext).pop('remove'),
              ),
              ListTile(
                leading: const Icon(Icons.block_rounded,
                    color: Colors.redAccent),
                title: const Text(
                  'Block User',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () => Navigator.of(sheetContext).pop('block'),
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined,
                    color: YanegiColors.textPrimary),
                title: const Text(
                  'Report User',
                  style: TextStyle(color: YanegiColors.textPrimary),
                ),
                onTap: () => Navigator.of(sheetContext).pop('report'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    if (action == 'remove') {
      await _removeCurrentFriend();
    } else if (action == 'block') {
      await _confirmAndBlockCurrentUser();
    } else if (action == 'report') {
      await _reportCurrentUser();
    }
  }

  /// Opens the safety & reporting flow for the viewed user.
  Future<void> _reportCurrentUser() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SafetyReportingScreen()),
    );
  }

  Future<void> _confirmAndBlockCurrentUser() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: YanegiColors.surface,
        title: const Text(
          'Block this user?',
          style: TextStyle(color: YanegiColors.textPrimary),
        ),
        content: const Text(
          'Blocking also removes your friendship. You won’t be able to '
          'message, friend, or join each other\'s events.',
          style: TextStyle(color: YanegiColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Block'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isActionBusy = true);
    // Drop the friendship first so the social graph is consistent, then block.
    await _friendService.removeFriend(_profileUid);
    await _blockService.blockUser(targetUid: _profileUid);
    if (!mounted) return;
    setState(() {
      _isActionBusy = false;
      _optimisticFriendState = FriendRelationshipState.notFriend;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('User blocked.')),
    );
  }

  Future<void> _showOwnProfileActionSheet() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: YanegiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        Widget tile(IconData icon, String label, String value,
            {bool danger = false}) {
          final color =
              danger ? Colors.redAccent : YanegiColors.textPrimary;
          return ListTile(
            leading: Icon(icon, color: color),
            title: Text(label,
                style: TextStyle(
                    color: color,
                    fontWeight: danger ? FontWeight.w700 : FontWeight.w500)),
            onTap: () => Navigator.of(sheetContext).pop(value),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tile(Icons.edit_outlined, 'Edit Profile', 'edit'),
              tile(Icons.share_rounded, 'Share Profile', 'share'),
              tile(Icons.block_outlined, 'Blocked Users', 'blocked'),
              tile(Icons.settings_rounded, 'Settings', 'settings'),
              tile(Icons.logout_rounded, 'Logout', 'logout', danger: true),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'edit':
        await _handlePrimaryAction();
        break;
      case 'share':
        _shareProfile();
        break;
      case 'blocked':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
        );
        break;
      case 'settings':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
        break;
      case 'logout':
        await _confirmAndLogout();
        break;
    }
  }

  /// Logout from the own-profile menu. Mirrors the documented Settings logout
  /// flow (cache wipe → service-cache invalidation → Google sign-out → Firebase
  /// sign-out → rebootstrap). Google sign-out MUST precede Firebase sign-out or
  /// the next "Continue with Google" silently reuses the previous account.
  Future<void> _confirmAndLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: YanegiColors.surface,
        title: const Text('Logout?',
            style: TextStyle(color: YanegiColors.textPrimary)),
        content: const Text(
          'You will need to sign in again to use Yanegi.',
          style: TextStyle(color: YanegiColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Logout',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      LocalProfileCache.clear(uid);
    }
    ChatPeerCache.clear();
    // Reset Riverpod service singletons so no stale streams survive the session
    // change. SocialProfileScreen is not a ConsumerWidget, so reach the nearest
    // container directly.
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      container.invalidate(chatRepositoryProvider);
      container.invalidate(eventServiceProvider);
      container.invalidate(exploreRecommendationServiceProvider);
    } catch (_) {
      // No ProviderScope ancestor — safe to ignore.
    }
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    AuthBootstrapperController.rebootstrap(navigationContext: context);
  }

  Future<void> _shareProfile() async {
    final userId = _profileUid.trim();
    if (userId.isEmpty || !mounted) return;

    final profileUrl = '${AppEnvironment.webBaseUrl}/profile/$userId';
    final name = _displayName.isNotEmpty ? _displayName : _username;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProfileShareSheet(
        userId: userId,
        name: name,
        username: _username,
        avatarUrl: _profileImageUrl,
        profileUrl: profileUrl,
      ),
    );
  }

  Future<void> _showProfileActionSheet() async {
    if (_isOwnProfile ||
        _currentUid.trim().isEmpty ||
        _profileUid.trim().isEmpty) {
      return;
    }

    final relationship =
        await _blockService.getRelationship(_currentUid, _profileUid);
    final blockedByMe = relationship.blockedByMe;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: YanegiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.share_rounded,
                    color: YanegiColors.textPrimary),
                title: const Text('Share Profile',
                    style: TextStyle(color: YanegiColors.textPrimary)),
                onTap: () => Navigator.of(sheetContext).pop('share'),
              ),
              ListTile(
                leading: Icon(
                  blockedByMe ? Icons.lock_open_rounded : Icons.block_rounded,
                  color: blockedByMe ? YanegiColors.primary : Colors.redAccent,
                ),
                title: Text(
                  blockedByMe ? 'Unblock User' : 'Block User',
                  style: TextStyle(
                    color: blockedByMe
                        ? YanegiColors.textPrimary
                        : Colors.redAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () => Navigator.of(sheetContext).pop(
                  blockedByMe ? 'unblock' : 'block',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined,
                    color: YanegiColors.textPrimary),
                title: const Text('Report User',
                    style: TextStyle(color: YanegiColors.textPrimary)),
                onTap: () => Navigator.of(sheetContext).pop('report'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    if (action == 'share') {
      _shareProfile();
      return;
    }

    if (action == 'report') {
      await _reportCurrentUser();
      return;
    }

    if (action == 'block') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: YanegiColors.surface,
          title: const Text(
            'Block this user?',
            style: TextStyle(color: YanegiColors.textPrimary),
          ),
          content: const Text(
            'You won’t be able to message, friend, or join each other\'s events.',
            style: TextStyle(color: YanegiColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Block'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await _blockService.blockUser(targetUid: _profileUid);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User blocked.')),
        );
      }
      return;
    }

    if (action == 'unblock') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: YanegiColors.surface,
          title: const Text(
            'Unblock this user?',
            style: TextStyle(color: YanegiColors.textPrimary),
          ),
          content: const Text(
            'You can interact with this user again after unblocking.',
            style: TextStyle(color: YanegiColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Unblock'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await _blockService.unblockUser(targetUid: _profileUid);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User unblocked.')),
        );
      }
    }
  }

  Widget _buildActionButtons() {
    if (_isOwnProfile) {
      return _glassButton(
        label: 'Edit Profile',
        icon: Icons.edit_outlined,
        onTap: _handlePrimaryAction,
        filled: true,
        solidPrimary: true,
      );
    }

    return StreamBuilder<FriendRelationshipState>(
      stream: _cachedFriendStateStream,
      builder: (context, snapshot) {
        // Clear the optimistic hint once the live stream confirms the same
        // state, so later real transitions (e.g. the other party accepts) are
        // not masked by a stale optimistic value.
        if (snapshot.hasData &&
            _optimisticFriendState != null &&
            snapshot.data == _optimisticFriendState) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _optimisticFriendState == snapshot.data) {
              setState(() => _optimisticFriendState = null);
            }
          });
        }

        final state = _optimisticFriendState ??
            (snapshot.data ?? FriendRelationshipState.notFriend);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFriendActionRow(state),
            _buildMutualFriendsLabel(),
          ],
        );
      },
    );
  }

  Widget _buildFriendActionRow(FriendRelationshipState state) {
    switch (state) {
      case FriendRelationshipState.notFriend:
        return _glassButton(
          label: 'Add Friend',
          icon: Icons.person_add_alt_rounded,
          onTap: _handlePrimaryAction,
          filled: true,
          solidPrimary: true,
          busy: _isActionBusy,
        );
      case FriendRelationshipState.requestSent:
        return _glassButton(
          label: 'Requested',
          icon: Icons.schedule_rounded,
          onTap: null,
          filled: true,
        );
      case FriendRelationshipState.requestReceived:
        return Row(
          children: [
            Expanded(
              child: _glassButton(
                label: 'Accept',
                icon: Icons.check_rounded,
                onTap: _acceptReceivedRequest,
                filled: true,
                busy: _isActionBusy,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _glassButton(
                label: 'Decline',
                icon: Icons.close_rounded,
                onTap: _declineReceivedRequest,
                filled: false,
              ),
            ),
          ],
        );
      case FriendRelationshipState.friend:
        return Row(
          children: [
            Expanded(
              child: _glassButton(
                label: 'Friends',
                icon: Icons.keyboard_arrow_down_rounded,
                onTap: _showFriendActionSheet,
                filled: true,
                solidPrimary: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _glassButton(
                label: 'Message',
                icon: Icons.chat_bubble_outline_rounded,
                onTap: _openDirectMessage,
                filled: false,
              ),
            ),
          ],
        );
    }
  }
}

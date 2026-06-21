// ignore_for_file: invalid_use_of_protected_member

part of '../../../screens/profile_social_screen.dart';

extension _ProfileDataController on _SocialProfileScreenState {
  void _initFriendStateStream() {
    if (_isOwnProfile || _currentUid.isEmpty || _profileUid.isEmpty) {
      _cachedFriendStateStream = null;
      return;
    }
    _cachedFriendStateStream =
        _friendService.friendStateStream(_currentUid, _profileUid);
  }

  Future<void> _loadMutualFriends() async {
    if (_isOwnProfile || _currentUid.isEmpty || _profileUid.isEmpty) return;
    final count =
        await _friendService.mutualFriendsCount(_currentUid, _profileUid);
    if (!mounted) return;
    setState(() => _mutualFriendsCount = count);
  }

  /// Refreshes all profile-derived data after an edit or rebootstrap.
  Future<void> _loadProfileData() async {
    if (!mounted) return;
    setState(() => _profileStreamRefreshTick++);
    unawaited(_loadFriendsPreview());
    unawaited(_loadInterestTags());
  }

  void _syncProfileFromSnapshot(Map<String, dynamic> data) {
    final usernameRaw = (data['username'] ?? '').toString().trim();
    final displayNameRaw = (data['name'] ?? '').toString().trim();
    final bioRaw = (data['bio'] ?? '').toString().trim();
    final avatarRaw = resolveRemoteMediaUrl(<dynamic>[
      data['photoUrl'],
      data['avatarUrl'],
      data['avatar_url'],
      data['profileImage'],
      data['profile_image'],
    ]);
    final bannerRaw = resolveRemoteMediaUrl(<dynamic>[
      data['bannerUrl'],
      data['banner_url'],
      data['bannerImage'],
      data['banner_image'],
    ]);
    final verificationStatus =
        (data['verificationStatus'] ?? '').toString().toLowerCase();
    final verifiedFlag = data['isVerified'] == true || data['verified'] == true;

    _displayName = displayNameRaw.isNotEmpty ? displayNameRaw : 'Unknown user';
    _username = usernameRaw.isNotEmpty
        ? (usernameRaw.startsWith('@') ? usernameRaw : '@$usernameRaw')
        : '@username';
    _bio = bioRaw.isNotEmpty ? bioRaw : 'No bio yet.';
    _profileImageUrl = _sanitizeAvatarUrl(avatarRaw);
    _bannerImageUrl = bannerRaw;
    _isVerified = verifiedFlag || verificationStatus == 'verified';
    _memberSince = _parseMemberSince(data);

    // `vibes` is the existing onboarding interest field — used as a fallback
    // source for the header interest tags when a user has no event history.
    final vibesRaw = data['vibes'];
    if (vibesRaw is List) {
      _vibes = vibesRaw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    } else {
      _vibes = const <String>[];
    }

    // Additional (gallery) photos — written by _ProfileGalleryController. Read
    // back here so they survive reloads and are visible on other users'
    // profiles. Absent field => empty (legacy accounts render cleanly).
    final galleryRaw = data['galleryPhotos'];
    if (galleryRaw is List) {
      _galleryPhotos = galleryRaw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty && isRemoteMediaUrl(e))
          .toList(growable: false);
    } else {
      _galleryPhotos = const <String>[];
    }
    debugPrint('GALLERY PHOTOS COUNT: ${_galleryPhotos.length} (rawType:${galleryRaw?.runtimeType}) profile=$_profileUid own=$_isOwnProfile');

    final promptsRaw = data['prompts'];
    if (promptsRaw is List) {
      _prompts = promptsRaw
          .whereType<Map>()
          .map((m) => <String, String>{
                'question': (m['question'] ?? '').toString(),
                'answer': (m['answer'] ?? '').toString(),
              })
          .where((p) =>
              (p['question'] ?? '').isNotEmpty && (p['answer'] ?? '').isNotEmpty)
          .toList(growable: false);
    } else {
      _prompts = const <Map<String, String>>[];
    }
    debugPrint('PROMPT VALUE FOUND: ${_prompts.length} (rawType:${promptsRaw?.runtimeType}) profile=$_profileUid own=$_isOwnProfile');
  }

  DateTime? _parseMemberSince(Map<String, dynamic> data) {
    final raw = data['createdAt'] ?? data['created_at'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    if (raw is int) {
      final millis = raw < 100000000000 ? raw * 1000 : raw;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    return null;
  }

  String _sanitizeAvatarUrl(String rawUrl) {
    final url = rawUrl.trim();
    if (url.isEmpty) return '';

    final uri = Uri.tryParse(url);
    final host = (uri?.host ?? '').toLowerCase();
    if (host.contains('googleusercontent.com') || host.contains('ggpht.com')) {
      return '';
    }

    return url;
  }

  Widget _buildMutualFriendsLabel() {
    final count = _mutualFriendsCount ?? 0;
    if (count <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_alt_rounded,
              size: 14, color: _textSecondaryColor),
          const SizedBox(width: 6),
          Text(
            count == 1 ? '1 mutual friend' : '$count mutual friends',
            style: TextStyle(
              color: _textSecondaryColor,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

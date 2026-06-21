import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../chat/data/firebase_chat_repository.dart';
import '../chat/providers/chat_providers.dart';
import '../models/user_profile.dart';
import '../auth/screens/auth_landing_page.dart';
import '../onboarding/auth_bootstrapper.dart';
import '../providers/explore_feed_provider.dart';
import '../services/block_service.dart';
import '../services/chat_peer_cache.dart';
import '../services/local_profile_cache.dart';
import '../services/friend_service.dart';
import '../services/media_storage_service.dart';
import '../services/reliable_upload_queue_service.dart';
import '../services/saved_events_service.dart';
import '../theme/yanegi_theme.dart';
import '../config/app_environment.dart';
import '../utils/error_handler.dart';
import '../utils/media_url_resolver.dart';
import '../widgets/app_avatars.dart';
import '../widgets/app_image_viewer.dart';
import '../widgets/guest_gate.dart';
import '../widgets/share_to_chat_sheet.dart';
import 'blocked_users_screen.dart';
import 'chat/chat_thread_screen.dart';
import 'profile_edit_screen.dart';
import 'crop_screen.dart';
import 'safety_reporting_screen.dart';
import 'settings_screen.dart';
import 'connections_screen.dart';
import 'event_detail_screen.dart';

part '../features/profile/controllers/profile_data_controller.dart';
part '../features/profile/controllers/profile_media_controller.dart';
part '../features/profile/controllers/hosted_events_controller.dart';
part '../features/profile/controllers/profile_view_controller.dart';
part '../features/profile/controllers/profile_sections_data.dart';
part '../features/profile/controllers/profile_sections_view.dart';
part '../features/profile/controllers/profile_gallery_controller.dart';
part '../features/friends/controllers/friend_action_controller.dart';
part '../features/profile/widgets/profile_media_header.dart';
part '../features/profile/widgets/profile_share_sheet.dart';

class SocialProfileScreen extends StatefulWidget {
  final String? profileUserId;
  final VoidCallback? onBackPressed;

  const SocialProfileScreen({
    super.key,
    this.profileUserId,
    this.onBackPressed,
  });

  @override
  State<SocialProfileScreen> createState() => _SocialProfileScreenState();
}

class _SocialProfileScreenState extends State<SocialProfileScreen> {
  final ScrollController _scrollController = ScrollController();
  final FriendService _friendService = FriendService();
  final FirebaseChatRepository _chatRepository = FirebaseChatRepository();
  final BlockService _blockService = BlockService();
  final MediaStorageService _mediaStorageService = MediaStorageService();

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _hostedEvents =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[];

  DocumentSnapshot<Map<String, dynamic>>? _lastHostedEventDoc;
  bool _isLoadingHostedEvents = false;
  bool _isLoadingMore = false;
  bool _isAutoFillingLiveHosted = false;
  bool _hasMoreHostedEvents = true;
  bool _isActionBusy = false;
  // True when a guest opened someone else's profile; build renders a blank
  // themed scaffold for the single frame before the post-frame pop fires.
  bool _gatedGuest = false;
  // True when a guest taps the profile tab; build shows a sign-in page.
  bool _isGuestOwnProfile = false;
  bool _isUploadingMedia = false;
  bool _isPickingMedia = false;
  UploadQueueState? _profileUploadState;
  UploadQueueState? _bannerUploadState;
  StreamSubscription<UploadStatusEvent>? _uploadStatusSub;

  String _displayName = '';
  String _username = '';
  String _bio = '';
  bool _isVerified = false;
  String _profileImageUrl = '';
  String _bannerImageUrl = '';
  int _profileStreamRefreshTick = 0;
  FriendRelationshipState? _optimisticFriendState;

  // Cached friend-relationship stream — stable identity so the StreamBuilder in
  // the action-button area does not resubscribe on every parent rebuild.
  Stream<FriendRelationshipState>? _cachedFriendStateStream;
  // Mutual-friends count with the viewed profile (null = not loaded / own profile).
  int? _mutualFriendsCount;

  // ─── Redesign state (header tags, friends strip, events tabs, cards) ───
  final SavedEventsService _savedEventsService = SavedEventsService();

  // Member-since timestamp parsed from the user doc (createdAt/created_at).
  DateTime? _memberSince;
  // Raw interest source from the user doc (onboarding `vibes`).
  List<String> _vibes = const <String>[];
  // Interest tags shown in the header — derived from hosted+joined event tags,
  // falling back to `vibes`. Lazily computed; empty until loaded.
  List<String> _interestTags = const <String>[];

  // Friends strip (avatars + count). For a friend profile, mutual friends are
  // ordered first. Loaded once per profile; refreshed on rebootstrap.
  final List<UserProfile> _friendsPreview = <UserProfile>[];
  int _friendsTotalCount = 0;
  Set<String> _mutualFriendIds = const <String>{};
  bool _isLoadingFriends = false;

  // Joined events for the "Joined" tab (lazy — loaded when the tab is opened).
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _joinedEvents =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  bool _isLoadingJoinedEvents = false;
  bool _joinedEventsLoaded = false;

  // Shared events count with the viewed profile (friend profile only).
  int? _sharedEventsCount;

  // Events section tab: 0 = Hosting, 1 = Joined.
  int _eventsTabIndex = 0;

  // ─── Hinge-style gallery + prompts ───
  // Gallery photo download URLs, stored at users/{uid}.galleryPhotos.
  List<String> _galleryPhotos = const <String>[];
  // Prompt cards, stored at users/{uid}.prompts as [{question, answer}].
  List<Map<String, String>> _prompts = const <Map<String, String>>[];
  // Per-slot upload-in-flight guard so taps don't double-fire.
  bool _isUploadingGalleryPhoto = false;

  static const int _hostedEventsPageSize = 8;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _liveHostedEvents {
    return _hostedEvents.where((doc) => _isHostedEventLive(doc.data())).toList(
          growable: false,
        );
  }

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _profileUid => (widget.profileUserId ?? _currentUid).trim();
  bool get _isOwnProfile => _profileUid.isEmpty || _profileUid == _currentUid;
  bool get _isDarkTheme => Theme.of(context).brightness == Brightness.dark;
  Color get _bgColor =>
      _isDarkTheme ? YanegiColors.background : const Color(0xFFF7F9FC);
  Color get _surfaceColor => _isDarkTheme ? YanegiColors.surface : Colors.white;
  Color get _textPrimaryColor =>
      _isDarkTheme ? YanegiColors.textPrimary : const Color(0xFF161C22);
  Color get _textSecondaryColor =>
      _isDarkTheme ? YanegiColors.textSecondary : const Color(0xFF5E6A7D);

  String get _profileUploadStoragePath => 'profile_images/$_currentUid/profile.jpg';
  String get _bannerUploadStoragePath => 'banner_images/$_currentUid/banner.jpg';

  @override
  void initState() {
    super.initState();
    // Guests (anonymous) may browse the map but must sign in to view another
    // person's profile. Bounce them back with a sign-in prompt before any
    // profile data loads.
    if (!_isOwnProfile && GuestGate.isGuest) {
      _gatedGuest = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).maybePop();
        GuestGate.promptSignIn(
          context,
          title: 'Sign in to view profiles',
          message:
              'Create a free account to see other people and connect with them.',
        );
      });
      return;
    }
    // Guest tapping the profile tab — show a full sign-in page instead of
    // loading empty profile data.
    if (_isOwnProfile && GuestGate.isGuest) {
      _isGuestOwnProfile = true;
      return;
    }
    _scrollController.addListener(_onScroll);
    _initFriendStateStream();
    _syncUploadStatesFromQueue();
    _uploadStatusSub = _mediaStorageService.uploadStatusStream.listen(
      _onUploadStatusEvent,
    );
    _loadInitialHostedEvents();
    // Eagerly load joined events so the header "Joined" stat is populated even
    // before the user opens the Joined tab.
    _loadJoinedEventsIfNeeded();
    unawaited(_loadMutualFriends());
    unawaited(_loadFriendsPreview());
    unawaited(_loadInterestTags());
    unawaited(_loadSharedEventsCount());
  }

  @override
  void dispose() {
    _uploadStatusSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_gatedGuest) {
      return Scaffold(backgroundColor: _bgColor, body: const SizedBox.shrink());
    }
    if (_isGuestOwnProfile) {
      return _buildGuestSignInPage();
    }
    if (_profileUid.isEmpty) {
      return SafeArea(
        child: Scaffold(
          backgroundColor: _bgColor,
          body: _buildProfileErrorState(),
        ),
      );
    }

    return Scaffold(
        backgroundColor: _bgColor,
        body: SafeArea(
          bottom: false,
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          key: ValueKey(_profileStreamRefreshTick),
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(_profileUid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return _buildProfileLoadingState();
            }

            if (snapshot.hasError) {
              return _buildProfileErrorState();
            }

            final profileMap =
                snapshot.data?.data() ?? const <String, dynamic>{};
            _syncProfileFromSnapshot(profileMap);

            final profileBody = SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildTopBar(),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHingeHeader(),
                        const SizedBox(height: 18),
                        _buildAboutSection(),
                        const SizedBox(height: 16),
                        _buildActionButtons(),
                        const SizedBox(height: 8),
                        _buildGalleryPromptFeed(),
                      ],
                    ),
                  ),
                ],
              ),
            );

            if (_isOwnProfile || _currentUid.trim().isEmpty) {
              return profileBody;
            }

            return StreamBuilder<BlockRelationship>(
              stream:
                  _blockService.relationshipStream(_currentUid, _profileUid),
              builder: (context, blockSnapshot) {
                final relation = blockSnapshot.data ??
                    const BlockRelationship(
                      blockedByMe: false,
                      blockedByThem: false,
                    );

                if (relation.isBlockedEitherWay) {
                  return _buildBlockedProfileView(
                    blockedByMe: relation.blockedByMe,
                    blockedByThem: relation.blockedByThem,
                  );
                }
                return profileBody;
              },
            );
          },
        ),
      ),
    );
  }

}

/// Two-option share sheet: "Share in Chat" + "Copy / Share Link"
/// Shown when the user taps Share Profile from the three-dot menu.

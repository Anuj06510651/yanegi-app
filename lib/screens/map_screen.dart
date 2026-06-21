import 'package:geolocator/geolocator.dart';
import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:confetti/confetti.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'activity_screen.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:yanegi/services/event_service.dart';
import 'package:yanegi/utils/error_handler.dart';
import 'chat/chat_hub_screen.dart';
import 'profile_social_screen.dart';
import '../theme/yanegi_theme.dart';
import '../config/map_config.dart';
import '../config/app_environment.dart';
import 'event_detail_screen.dart';
import 'map_picker_screen.dart';
import 'cover_crop_screen.dart';
import '../models/event_node.dart';
import '../models/event_model.dart';
import '../models/event_creation_model.dart';
import '../models/ranked_explore_event.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'filter_bottom_sheet.dart';
import '../controllers/filter_controller.dart';
import '../providers/explore_feed_provider.dart';
import '../services/explore_recommendation_service.dart';
import '../services/activity_notification_service.dart';
import '../services/media_storage_service.dart';
import '../services/app_theme_service.dart';
import '../utils/event_avatar_utils.dart';
import '../widgets/friends_going_strip.dart';
import '../widgets/share_to_chat_sheet.dart';
import '../widgets/first_launch_tutorial.dart';
import '../widgets/app_rating_dialog.dart';
import '../services/event_end_detector_service.dart';
import 'event_recap_screen.dart';

part '../features/map/controllers/map_location_controller.dart';
part '../features/map/controllers/map_events_controller.dart';
part '../features/map/controllers/map_markers_controller.dart';
part '../features/map/controllers/map_ui_controller.dart';
part '../features/map/controllers/map_explore_controller.dart';
part '../features/map/widgets/create_event_sheet.dart';
part '../features/map/widgets/explore_card_interaction.dart';
part '../features/map/widgets/explore_skeleton_card.dart';
part '../features/map/widgets/user_location_marker.dart';
part '../features/map/widgets/map_share_tile.dart';
part '../features/map/widgets/explore_feed_models.dart';

/// Immersive social discovery map screen
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class MapWidget extends ConsumerWidget {
  const MapWidget({
    super.key,
    required this.eventNodes,
    required this.currentUserLocation,
    required this.mapBuilder,
  });

  final List<EventNode> eventNodes;
  final LatLng? currentUserLocation;
  final Widget Function(List<EventNode> filteredNodes) mapBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterCtrl = ref.read(filterProvider.notifier);
    ref.watch(filterProvider);
    final filteredNodes =
        filterCtrl.applyFilters(eventNodes, currentUserLocation);
    return mapBuilder(filteredNodes);
  }
}

class ExploreListWidget extends ConsumerWidget {
  const ExploreListWidget({
    super.key,
    required this.userLocation,
    required this.exploreBuilder,
  });

  final LatLng? userLocation;
  final Widget Function(
    AsyncValue<ExplorePaginatedFeedState> rankedExploreAsync,
    ExploreFeedRequest request,
  ) exploreBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(filterProvider);
    final request = ExploreFeedRequest(
      filter: filterState,
      userLocation: userLocation,
    );
    final rankedExploreAsync = ref.watch(explorePaginatedFeedProvider(request));
    return exploreBuilder(rankedExploreAsync, request);
  }
}

class TopBarWidget extends StatelessWidget {
  const TopBarWidget({
    super.key,
    required this.navIndex,
    required this.insets,
    required this.searchBar,
    required this.actionsGroup,
  });

  final int navIndex;
  final EdgeInsets insets;
  final Widget searchBar;
  final Widget actionsGroup;

  @override
  Widget build(BuildContext context) {
    if (navIndex == 1 || navIndex == 2) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: insets.top + 8,
      left: 4,
      right: 4,
      child: Row(
        children: [
          Expanded(child: searchBar),
          const SizedBox(width: 8),
          actionsGroup,
        ],
      ),
    );
  }
}

class _MapScreenState extends ConsumerState<MapScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _exploreSearchController =
      TextEditingController();
  int _navIndex = 0;
  int _previousTabIndexBeforeProfile = 0;
  double _zoomLevel = 14.0;
  bool get _isDarkTheme => Theme.of(context).brightness == Brightness.dark;
  LatLng? _currentUserLocation;
  bool _isLoadingLocation = true;
  bool _mapReady = false;
  bool _eventsLoadedAfterMapReady = false;
  bool _didAnimateToInitialUserLocation = false;
  LatLng? _lastKnownMapCenter;
  Timer? _cameraAnimationTimer;
  Timer? _zoomCommitTimer;
  Timer? _eventExpiryTimer;
  bool _isLocationIssueSheetOpen = false;
  bool _showTutorial = false;

  final MapController _mapController = MapController();
  final ActivityNotificationService _notificationService =
      ActivityNotificationService();
  final EventService _eventService = EventService();
  final ConfettiController _confettiController =
      ConfettiController(duration: const Duration(milliseconds: 1200));

  // Cached so the same stream object is passed to StreamBuilder every build.
  // Creating a new stream each build would tear down and recreate the Firestore
  // listener on every setState, causing WatchStream churn and BLASTBufferQueue errors.
  late final Stream<int> _notifCountStream;
  late final Stream<int> _chatUnreadCountStream;

  String _selectedExploreChip = 'All';
  int _exploreRefreshCycle = 0;
  final Set<String> _joiningExploreEventIds = <String>{};
  String? _selectedMarkerEventId;

  static const List<String> _exploreChips = [
    'All',
    'Nearby',
    'Today',
    'Free',
    'Trending',
    'Nightlife',
    'Chill',
  ];

  final List<EventNode> _eventNodes = [];
  StreamSubscription<QuerySnapshot>? _eventsSub;
  List<Marker> _cachedEventMarkers = const <Marker>[];
  String _markerCacheKey = '';
  String _lastMapBuildDebugKey = '';

  static const LatLng _nycCenter = LatLng(28.6139, 77.2090);

  // Mapbox raster styles — vibrant Streets in light, modern Dark in dark mode.
  // Mapbox tiles ship labels baked in, so a single tile layer is all we need.
  String get _mapBaseUrlTemplate => MapConfig.rasterTileUrl(
      _isDarkTheme ? MapConfig.darkStyleId : MapConfig.lightStyleId);

  Color get _screenBackground =>
      _isDarkTheme ? const Color(0xFF000000) : const Color(0xFFF4F6FA);

  Color get _searchBarColor => _isDarkTheme
      ? const Color(0xFF1E1E28).withAlpha(235)
      : Colors.white.withAlpha(245);

  Color get _searchBarBorderColor =>
      _isDarkTheme ? Colors.white.withAlpha(20) : Colors.black.withAlpha(14);

  Color get _searchBarIconColor =>
      _isDarkTheme ? Colors.white.withAlpha(180) : Colors.black87;

  Color get _searchBarHintColor =>
      _isDarkTheme ? Colors.white.withAlpha(120) : Colors.black45;

  Color get _inputFieldBackground =>
      _isDarkTheme ? const Color(0xFF1E1E28) : Colors.white;

  Color get _inputFieldBorderColor =>
      _isDarkTheme ? Colors.white.withAlpha(20) : Colors.black.withAlpha(12);

  Color get _inputFieldTextColor =>
      _isDarkTheme ? Colors.white : Colors.black87;

  Color get _inputFieldHintColor =>
      _isDarkTheme ? Colors.white38 : Colors.black38;

  Color get _toggleTileBackground =>
      _isDarkTheme ? const Color(0xFF171D2A) : Colors.white.withAlpha(245);

  Color get _eventCreationLabelColor =>
      _isDarkTheme ? Colors.white : Colors.black87;

  Color get _topActionButtonColor =>
      _isDarkTheme ? const Color(0xFF121722) : Colors.white.withAlpha(240);

  Color get _topActionBorderColor =>
      _isDarkTheme ? Colors.white.withAlpha(16) : Colors.black.withAlpha(12);

  Color get _topActionIconColor =>
      _isDarkTheme ? Colors.white.withAlpha(220) : Colors.black87;

  Color get _taskbarColor =>
      _isDarkTheme ? const Color(0xFF121722) : Colors.white.withAlpha(245);

  Color get _taskbarBorderColor =>
      _isDarkTheme ? Colors.white.withAlpha(14) : Colors.black.withAlpha(10);

  Color get _taskbarIconActiveColor =>
      _isDarkTheme ? Colors.white : YanegiColors.primary;

  Color get _taskbarIconInactiveColor =>
      _isDarkTheme ? YanegiColors.textSecondary : Colors.black45;

  Color get _tabSurfaceColor =>
      _isDarkTheme ? const Color(0xFF171D2A) : Colors.white.withAlpha(245);

  Color get _tabBorderColor =>
      _isDarkTheme ? Colors.white.withAlpha(14) : Colors.black.withAlpha(14);

  Color get _tabPrimaryTextColor =>
      _isDarkTheme ? Colors.white : Colors.black87;

  Color get _tabSecondaryTextColor =>
      _isDarkTheme ? Colors.white.withAlpha(150) : Colors.black54;

  bool get _useLightweightWebMapStyle => kIsWeb;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notifCountStream = _notificationService.unreadCountStream();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _chatUnreadCountStream = uid.isEmpty
        ? Stream.value(0)
        : (() async* {
            // Emit 0 immediately so the badge renders without a Firestore hit.
            // The real listener starts 3 s after launch so it does not compete
            // with map tiles, location, and the events stream during startup.
            yield 0;
            await Future<void>.delayed(const Duration(seconds: 3));
            yield* FirebaseFirestore.instance
                .collection('chats')
                .where('participantIds', arrayContains: uid)
                .snapshots(includeMetadataChanges: false)
                .map((snap) {
              var total = 0;
              for (final doc in snap.docs) {
                final data = doc.data();
                final deletedFor = data['deletedFor'];
                if (deletedFor is List && deletedFor.contains(uid)) continue;
                final mutedBy = data['mutedBy'];
                if (mutedBy is List && mutedBy.contains(uid)) continue;
                final raw = data['unreadCount'];
                if (raw is Map) {
                  final v = raw[uid];
                  if (v is int) total += v;
                }
              }
              return total;
            }).handleError((Object _) => 0);
          })();
    // Provider write deferred so it never runs during a build frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncActiveTabProviderFromIndex(_navIndex);
    });
    _initLocation();
    _startEventExpiryPruner();
  }

  @override
  void dispose() {
    _cameraAnimationTimer?.cancel();
    _zoomCommitTimer?.cancel();
    _eventExpiryTimer?.cancel();
    _debounce?.cancel();
    _eventsSub?.cancel();
    _mapController.dispose();
    _confettiController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkEndedEvents();
    }
  }

  Timer? _debounce;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewPadding;

    return Scaffold(
      backgroundColor: _screenBackground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: MapWidget(
              eventNodes: _eventNodes,
              currentUserLocation: _currentUserLocation,
              mapBuilder: _buildMapLayer,
            ),
          ),

          // Subtle depth overlays for a richer map look
          _buildMapAtmosphereOverlay(),

          TopBarWidget(
            navIndex: _navIndex,
            insets: insets,
            searchBar: _buildSearchBar(),
            actionsGroup: _buildTopActionsGroup(),
          ),

          Positioned.fill(
            child: Visibility(
              visible: _navIndex == 1,
              maintainState: true,
              child: ExploreListWidget(
                userLocation: _currentUserLocation,
                exploreBuilder: _buildYanegiExplorePage,
              ),
            ),
          ),

          Positioned.fill(
            child: Visibility(
              visible: _navIndex == 2,
              maintainState: true,
              child: const ChatHubScreen(),
            ),
          ),

          Positioned.fill(
            child: Visibility(
              visible: _navIndex == 3,
              maintainState: true,
              child: SocialProfileScreen(
                onBackPressed: () {
                  if (!mounted) return;
                  setState(() {
                    _navIndex = _previousTabIndexBeforeProfile;
                  });
                  _syncActiveTabProviderFromIndex(
                      _previousTabIndexBeforeProfile);
                },
              ),
            ),
          ),

          // First-launch tutorial overlay
          if (_showTutorial)
            Positioned.fill(
              child: FirstLaunchTutorial(
                onDone: () => setState(() => _showTutorial = false),
              ),
            ),

          // First-event confetti burst — fires from top center
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 35,
              gravity: 0.3,
              emissionFrequency: 0.06,
              colors: const [
                Color(0xFF3B82F6),
                Color(0xFF22E7A2),
                Color(0xFFFBBF24),
                Color(0xFFF472B6),
                Color(0xFFA78BFA),
                Color(0xFFFF6B6B),
              ],
              createParticlePath: (size) {
                final path = ui.Path();
                path.addOval(Rect.fromCircle(
                    center: Offset(size.width / 2, size.height / 2),
                    radius: size.width / 2));
                return path;
              },
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildMinimalBottomNav(),
          ),
        ],
      ),
    );
  }

}

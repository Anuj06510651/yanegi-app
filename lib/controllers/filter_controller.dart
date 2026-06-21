import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/event_node.dart';

class FilterModel {
  final List<String> categories;
  final List<String> vibes;
  final String dateFilter; // 'today', 'tomorrow', 'weekend', 'anytime'
  final int radiusKm;
  final bool freeOnly;
  final bool friendsGoing;
  final bool smallGroups;
  final bool publicOnly;
  final String searchQuery;

  FilterModel({
    this.categories = const [],
    this.vibes = const [],
    this.dateFilter = 'anytime',
    this.radiusKm = 35,
    this.freeOnly = false,
    this.friendsGoing = false,
    this.smallGroups = false,
    this.publicOnly = false,
    this.searchQuery = '',
  });

  bool hasActiveFilters() {
    return categories.isNotEmpty ||
           vibes.isNotEmpty ||
           dateFilter != 'anytime' ||
           radiusKm != 35 ||
           freeOnly ||
           friendsGoing ||
           smallGroups ||
           publicOnly ||
           searchQuery.isNotEmpty;
  }

  FilterModel copyWith({
    List<String>? categories,
    List<String>? vibes,
    String? dateFilter,
    int? radiusKm,
    bool? freeOnly,
    bool? friendsGoing,
    bool? smallGroups,
    bool? publicOnly,
    String? searchQuery,
  }) {
    return FilterModel(
      categories: categories ?? this.categories,
      vibes: vibes ?? this.vibes,
      dateFilter: dateFilter ?? this.dateFilter,
      radiusKm: radiusKm ?? this.radiusKm,
      freeOnly: freeOnly ?? this.freeOnly,
      friendsGoing: friendsGoing ?? this.friendsGoing,
      smallGroups: smallGroups ?? this.smallGroups,
      publicOnly: publicOnly ?? this.publicOnly,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

class FilterController extends StateNotifier<FilterModel> {
  FilterController() : super(FilterModel());

  void updateFilters({
    List<String>? categories,
    List<String>? vibes,
    String? dateFilter,
    int? radiusKm,
    bool? freeOnly,
    bool? friendsGoing,
    bool? smallGroups,
    bool? publicOnly,
    String? searchQuery,
  }) {
    state = state.copyWith(
      categories: categories,
      vibes: vibes,
      dateFilter: dateFilter,
      radiusKm: radiusKm,
      freeOnly: freeOnly,
      friendsGoing: friendsGoing,
      smallGroups: smallGroups,
      publicOnly: publicOnly,
      searchQuery: searchQuery,
    );
  }

  void clearFilters() {
    state = FilterModel();
  }

  List<EventNode> applyFilters(List<EventNode> allEvents, LatLng? userLocation) {
    return allEvents.where((event) {
      if (state.searchQuery.trim().isNotEmpty) {
        final q = state.searchQuery.toLowerCase().trim();
        final titleMatch = (event.label ?? '').toLowerCase().contains(q);
        final hostMatch = event.hostName.toLowerCase().contains(q);
        final vibesMatch = event.vibes.any((v) => v.toLowerCase().contains(q));
        if (!titleMatch && !hostMatch && !vibesMatch) return false;
      }
      if (state.categories.isNotEmpty) {
        if (!state.categories.any((c) => event.categories.contains(c))) return false;
      }
      if (state.vibes.isNotEmpty) {
        if (!state.vibes.any((v) => event.vibes.contains(v))) return false;
      }
      if (state.dateFilter != 'anytime' && event.date != null) {
        final now = DateTime.now();
        final eventDate = event.date!;
        if (state.dateFilter == 'today') {
          if (eventDate.year != now.year || eventDate.month != now.month || eventDate.day != now.day) return false;
        } else if (state.dateFilter == 'tomorrow') {
          final tomorrow = now.add(const Duration(days: 1));
          if (eventDate.year != tomorrow.year || eventDate.month != tomorrow.month || eventDate.day != tomorrow.day) return false;
        } else if (state.dateFilter == 'weekend') {
          if (eventDate.weekday != DateTime.saturday && eventDate.weekday != DateTime.sunday && eventDate.weekday != DateTime.friday) return false;
        }
      }
      if (state.freeOnly && event.price > 0) return false;
      if (state.publicOnly && !event.isPublic) return false;
      if (state.smallGroups && event.maxCapacity > 6) return false;
      
      if (userLocation != null) {
        const distance = Distance();
        final km = distance.as(LengthUnit.Kilometer, userLocation, event.latLng);
        if (km > state.radiusKm) return false;
      }
      return true;
    }).toList();
  }
}

final filterProvider = StateNotifierProvider<FilterController, FilterModel>((ref) {
  return FilterController();
});

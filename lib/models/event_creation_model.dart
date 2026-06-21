class EventCreationModel {
  final String title;
  final String description;
  final String timeLabel;
  final String expectedAttendeesText;
  final String visibility; // public | private
  final bool isApprovalRequired;
  final int maxCapacity;
  final bool usePreciseLocation;
  final bool hideExactLocationUntilApproved;
  final List<String> selectedTags;
  final int ageRangeMin;
  final int ageRangeMax;
  final String? selectedEmoji;
  final String? bannerImagePath;
  final String meetingPoint;

  const EventCreationModel({
    this.title = '',
    this.description = '',
    this.timeLabel = '',
    this.expectedAttendeesText = '',
    this.visibility = 'public',
    this.isApprovalRequired = true,
    this.maxCapacity = 10,
    this.usePreciseLocation = false,
    this.hideExactLocationUntilApproved = false,
    this.selectedTags = const [],
    this.ageRangeMin = 18,
    this.ageRangeMax = 30,
    this.selectedEmoji,
    this.bannerImagePath,
    this.meetingPoint = '',
  });

  bool get isPublic => visibility == 'public';
  bool get hasRequiredFields =>
      title.trim().isNotEmpty && timeLabel.trim().isNotEmpty;

  EventCreationModel copyWith({
    String? title,
    String? description,
    String? timeLabel,
    String? expectedAttendeesText,
    String? visibility,
    bool? isApprovalRequired,
    int? maxCapacity,
    bool? usePreciseLocation,
    bool? hideExactLocationUntilApproved,
    List<String>? selectedTags,
    int? ageRangeMin,
    int? ageRangeMax,
    String? selectedEmoji,
    String? bannerImagePath,
    String? meetingPoint,
    bool clearSelectedEmoji = false,
    bool clearBannerImagePath = false,
  }) {
    return EventCreationModel(
      title: title ?? this.title,
      description: description ?? this.description,
      timeLabel: timeLabel ?? this.timeLabel,
      expectedAttendeesText: expectedAttendeesText ?? this.expectedAttendeesText,
      visibility: visibility ?? this.visibility,
      isApprovalRequired: isApprovalRequired ?? this.isApprovalRequired,
      maxCapacity: maxCapacity ?? this.maxCapacity,
      usePreciseLocation: usePreciseLocation ?? this.usePreciseLocation,
      hideExactLocationUntilApproved:
          hideExactLocationUntilApproved ?? this.hideExactLocationUntilApproved,
      selectedTags: selectedTags ?? this.selectedTags,
      ageRangeMin: ageRangeMin ?? this.ageRangeMin,
      ageRangeMax: ageRangeMax ?? this.ageRangeMax,
      selectedEmoji: clearSelectedEmoji
          ? null
          : (selectedEmoji ?? this.selectedEmoji),
      bannerImagePath: clearBannerImagePath
          ? null
          : (bannerImagePath ?? this.bannerImagePath),
      meetingPoint: meetingPoint ?? this.meetingPoint,
    );
  }
}

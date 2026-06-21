part of '../../../screens/map_screen.dart';

class _CreateEventSheet extends StatefulWidget {
  final LatLng? initialUserLocation;
  final ValueChanged<EventNode> onCreateEvent;
  final VoidCallback? onSubmitStarted;

  const _CreateEventSheet({
    required this.onCreateEvent,
    this.initialUserLocation,
    this.onSubmitStarted,
  });

  @override
  State<_CreateEventSheet> createState() => _CreateEventSheetState();
}

class _CreateEventSheetState extends State<_CreateEventSheet> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _peopleCountController = TextEditingController();
  final _meetingPointController = TextEditingController();
  final ScrollController _formScrollController = ScrollController();
  final PageController _pageController = PageController();
  int _currentPage = 0;
  static const int _totalPages = 4;
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _descriptionFocusNode = FocusNode();
  final FocusNode _peopleFocusNode = FocusNode();
  final FocusNode _meetingPointFocusNode = FocusNode();
  final GlobalKey _nameFieldKey = GlobalKey();
  final GlobalKey _descriptionFieldKey = GlobalKey();
  final GlobalKey _peopleFieldKey = GlobalKey();
  final GlobalKey _meetingPointFieldKey = GlobalKey();
  final MediaStorageService _mediaStorageService = MediaStorageService();

  LatLng? _currentUserLocation;
  LatLng? _selectedLocation;
  String _selectedLocationName = '';
  EventCreationModel _formModel = const EventCreationModel();
  bool _showValidationErrors = false;
  bool _isPickingBannerImage = false;
  bool _isSubmitting = false;
  DateTime? _selectedStartAtLocal;

  RangeValues _ageRange = const RangeValues(18, 30);
  final List<String> _eventTags = [
    'Music',
    'Art',
    'Food',
    'Sports',
    'Tech',
    'Social',
    'Networking',
    'Party',
    'Outdoor',
    'Indoor',
  ];

  bool get _isDarkTheme => Theme.of(context).brightness == Brightness.dark;

  ThemeData get _theme => Theme.of(context);
  ColorScheme get _scheme => _theme.colorScheme;

  Color get _sheetBackgroundColor =>
      _isDarkTheme ? const Color(0xFF12121A) : _scheme.surface;
  Color get _sheetTitleColor => _scheme.onSurface;
  Color get _sheetMutedColor =>
      _isDarkTheme ? Colors.white.withAlpha(150) : _scheme.onSurfaceVariant;
  Color get _sheetHandleColor =>
      _isDarkTheme ? Colors.white24 : Colors.black.withAlpha(24);
  Color get _closeButtonBackground =>
      _isDarkTheme ? Colors.white.withAlpha(15) : Colors.black.withAlpha(8);
  Color get _closeButtonIconColor =>
      _isDarkTheme ? Colors.white70 : Colors.black54;
  Color get _visibilityChipBackground =>
      _isDarkTheme ? const Color(0xFF1E1E28) : _scheme.surfaceContainerHighest;
  Color get _visibilityChipSelectedBackground =>
      _scheme.primary.withAlpha(_isDarkTheme ? 46 : 30);
  Color get _visibilityChipBorder =>
      _isDarkTheme ? Colors.white.withAlpha(24) : Colors.black.withAlpha(16);

  Color get _inputFieldBackground =>
      _isDarkTheme ? const Color(0xFF1E1E28) : _scheme.surface;
  Color get _inputFieldBorderColor =>
      _isDarkTheme ? Colors.white.withAlpha(20) : Colors.black.withAlpha(12);
  Color get _inputFieldTextColor => _sheetTitleColor;
  Color get _inputFieldHintColor => _sheetMutedColor;

  @override
  void initState() {
    super.initState();
    _currentUserLocation = widget.initialUserLocation;
    _nameFocusNode
        .addListener(() => _ensureFieldVisible(_nameFieldKey, _nameFocusNode));
    _descriptionFocusNode.addListener(
      () => _ensureFieldVisible(_descriptionFieldKey, _descriptionFocusNode),
    );
    _peopleFocusNode.addListener(
      () => _ensureFieldVisible(_peopleFieldKey, _peopleFocusNode),
    );
    _meetingPointFocusNode.addListener(
      () => _ensureFieldVisible(_meetingPointFieldKey, _meetingPointFocusNode),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _peopleCountController.dispose();
    _meetingPointController.dispose();
    _formScrollController.dispose();
    _pageController.dispose();
    _nameFocusNode.dispose();
    _descriptionFocusNode.dispose();
    _peopleFocusNode.dispose();
    _meetingPointFocusNode.dispose();
    super.dispose();
  }

  void _ensureFieldVisible(GlobalKey fieldKey, FocusNode focusNode) {
    if (!focusNode.hasFocus) return;
    final fieldContext = fieldKey.currentContext;
    if (fieldContext == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        fieldContext,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        alignment: 0.2,
      );
    });
  }

  Future<void> _selectDateTime() async {
    final now = DateTime.now();
    final pickerTheme = Theme.of(context).copyWith(
      colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: const Color(0xFF3B82F6),
          ),
    );
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: pickerTheme,
          child: child!,
        );
      },
    );

    if (pickedDate == null || !mounted) return;

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: pickerTheme,
          child: child!,
        );
      },
    );

    if (pickedTime == null || !mounted) return;

    final selectedDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (!selectedDateTime.isAfter(now)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please choose a future date and time.'),
        ),
      );
      return;
    }

    setState(() {
      _selectedStartAtLocal = selectedDateTime;
      _formModel = _formModel.copyWith(
        timeLabel: DateFormat('EEE, MMM d • h:mm a').format(selectedDateTime),
      );
    });
  }

  void _toggleTag(String tag) {
    final updatedTags = List<String>.from(_formModel.selectedTags);
    setState(() {
      if (updatedTags.contains(tag)) {
        updatedTags.remove(tag);
      } else {
        updatedTags.add(tag);
      }
      _formModel = _formModel.copyWith(selectedTags: updatedTags);
    });
  }

  Future<void> _pickBannerImage() async {
    if (_isPickingBannerImage) {
      debugPrint('[banner] pick skipped (already running)');
      return;
    }

    _isPickingBannerImage = true;
    debugPrint('[banner] pick started');

    try {
      final picker = ImagePicker();
      final lostData = await picker.retrieveLostData();

      XFile? picked;
      if (lostData.files != null && lostData.files!.isNotEmpty) {
        debugPrint('[banner] recovered lost image picker data');
        picked = lostData.files!.first;
      } else {
        if (lostData.exception != null) {
          debugPrint('[banner] lost-data recovery: ${lostData.exception}');
        }
        picked = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 95,
        );
        if (picked == null) {
          debugPrint('[banner] user cancelled image selection');
          return;
        }
      }

      if (!mounted) return;

      // Open crop screen — user frames the 16:9 cover before saving
      final croppedPath = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => CoverCropScreen(imagePath: picked!.path),
          fullscreenDialog: true,
        ),
      );

      if (!mounted) return;
      if (croppedPath == null) {
        debugPrint('[banner] user cancelled crop');
        return;
      }

      setState(() {
        _formModel = _formModel.copyWith(bannerImagePath: croppedPath);
      });
      debugPrint('[banner] cropped path set: $croppedPath');
    } catch (e) {
      debugPrint('[banner] pick failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not select image. Please try again.'),
        ),
      );
    } finally {
      _isPickingBannerImage = false;
      debugPrint('[banner] pick ended');
    }
  }

  Future<String?> _uploadEventBannerToStorage({
    required String eventId,
    required String localPath,
  }) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        debugPrint('[banner] file missing: $localPath');
        return null;
      }

      final baseUrl = await _mediaStorageService.uploadEventImage(
        eventId: eventId,
        localFilePath: localPath,
      );
      debugPrint('[banner] upload success');
      return baseUrl;
    } catch (e) {
      debugPrint('[banner] upload failed: $e');
      return null;
    }
  }

  LatLng _approximateLocation(LatLng location) {
    return LatLng(
      (location.latitude * 100).round() / 100,
      (location.longitude * 100).round() / 100,
    );
  }

  Future<void> _openMapLocationPicker() async {
    final selected = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialUserLocation: _currentUserLocation,
          initialSelectedLocation: _selectedLocation,
        ),
      ),
    );

    if (!mounted || selected == null) return;
    final lat = (selected['lat'] as num?)?.toDouble();
    final lng = (selected['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    setState(() {
      _selectedLocation = LatLng(lat, lng);
      _selectedLocationName = (selected['name'] as String? ?? '').trim();
    });
  }

  String _avatarFromTags() {
    if (_formModel.selectedTags.isEmpty) return kEventAvatarAssets.first;
    return kEmojiByTag[_formModel.selectedTags.first] ??
        kEventAvatarAssets.first;
  }

  Color _colorFromTags() {
    if (_formModel.selectedTags.isEmpty) return YanegiColors.accentViolet;

    const colors = {
      'Music': YanegiColors.accentViolet,
      'Art': YanegiColors.accentPink,
      'Food': YanegiColors.accentCyan,
      'Sports': YanegiColors.accentGreen,
      'Tech': Color(0xFF64B5F6),
      'Social': YanegiColors.primary,
      'Networking': Color(0xFF9575CD),
      'Party': Color(0xFF3B82F6),
      'Outdoor': Color(0xFF81C784),
      'Indoor': Color(0xFFB0BEC5),
    };

    return colors[_formModel.selectedTags.first] ?? YanegiColors.accentViolet;
  }

  bool get _isFormValid {
    final capacity = int.tryParse(_formModel.expectedAttendeesText.trim());
    return _formModel.title.trim().isNotEmpty &&
        _selectedStartAtLocal != null &&
        capacity != null &&
        capacity >= 2 &&
        _selectedLocation != null;
  }

  String? get _titleError {
    if (!_showValidationErrors || _formModel.title.trim().isNotEmpty) {
      return null;
    }
    return 'Event name is required';
  }

  String? get _timeError {
    if (!_showValidationErrors || _selectedStartAtLocal != null) {
      return null;
    }
    return 'Please select date and time';
  }

  String? get _locationError {
    if (!_showValidationErrors || _selectedLocation != null) return null;
    return 'Location is required';
  }

  String? get _capacityError {
    if (!_showValidationErrors) return null;
    final capacity = int.tryParse(_formModel.expectedAttendeesText.trim());
    if (capacity == null || capacity < 2) {
      return 'Minimum 2 participants required';
    }
    return null;
  }

  Future<void> _createEvent() async {
    if (_isSubmitting) return;

    setState(() {
      _showValidationErrors = true;
    });

    if (!_isFormValid) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final selectedLocation = _selectedLocation!;
    final approximateLocation = _approximateLocation(selectedLocation);
    final selectedStartAtLocal = _selectedStartAtLocal!;
    final selectedStartAtUtc = selectedStartAtLocal.toUtc();
    final selectedEndAtUtc = selectedStartAtUtc.add(const Duration(hours: 2));

    final ageMin = _ageRange.start.round();
    final ageMax = _ageRange.end.round();

    final capacityInput = _formModel.expectedAttendeesText.trim();
    final expectedPeople = int.tryParse(capacityInput);
    if (expectedPeople == null || expectedPeople < 2) {
      setState(() {
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimum 2 participants required')),
      );
      return;
    }
    final safeActivity = (expectedPeople / 100).clamp(0.2, 1.0);

    final hostId = FirebaseAuth.instance.currentUser?.uid ?? 'unknown_user';
    final emoji = _formModel.selectedEmoji ?? _avatarFromTags();
    final localBannerPath = _formModel.bannerImagePath;
    final messenger = ScaffoldMessenger.maybeOf(context);

    widget.onSubmitStarted?.call();
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 10),
            Text('Creating event...'),
          ],
        ),
      ),
    );

    if (mounted) {
      Navigator.of(context).pop();
    }

    String? createdEventId;
    try {
      createdEventId = await EventService().createEvent(
        title: _formModel.title.trim(),
        location:
            GeoPoint(selectedLocation.latitude, selectedLocation.longitude),
        hostId: hostId,
        eventAvatar: emoji,
        startAt: selectedStartAtUtc,
        endAt: selectedEndAtUtc,
        description: _formModel.description.trim(),
        maxCapacity: expectedPeople,
        visibility: _formModel.visibility,
        isApprovalRequired: _formModel.isApprovalRequired,
        bannerImagePath: null,
        timeLabel: _formModel.timeLabel,
        tags: [
          ..._formModel.selectedTags,
          'Age: $ageMin–$ageMax',
        ],
        locationName: _selectedLocationName.isNotEmpty
            ? _selectedLocationName
            : 'Location selected',
        meetingPoint: _formModel.meetingPoint.trim(),
        hideExactLocationUntilApproved:
            _formModel.hideExactLocationUntilApproved,
        approximateLocation: GeoPoint(
          approximateLocation.latitude,
          approximateLocation.longitude,
        ),
        ageRangeMin: ageMin,
        ageRangeMax: ageMax,
      );

      String? uploadedBannerUrl;
      if (localBannerPath != null && localBannerPath.trim().isNotEmpty) {
        try {
          uploadedBannerUrl = await _uploadEventBannerToStorage(
            eventId: createdEventId,
            localPath: localBannerPath,
          );

          if (uploadedBannerUrl != null && uploadedBannerUrl.isNotEmpty) {
            await FirebaseFirestore.instance
                .collection('events')
                .doc(createdEventId)
                .set({
              'thumbnailUrl': uploadedBannerUrl,
              'bannerUrl': uploadedBannerUrl,
              'bannerImagePath': uploadedBannerUrl,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        } catch (e) {
          debugPrint('Banner upload failed for event $createdEventId: $e');
        }
      }

      final newEvent = EventNode(
        id: createdEventId,
        latLng: selectedLocation,
        emoji: emoji,
        label: _formModel.title.trim(),
        color: _colorFromTags(),
        activityLevel: safeActivity,
        bannerImagePath: uploadedBannerUrl,
        currentAttendees: 1,
        maxCapacity: expectedPeople,
        categories: List<String>.from(_formModel.selectedTags),
        isPublic: _formModel.isPublic,
        visibility: _formModel.visibility,
        isApprovalRequired: _formModel.isApprovalRequired,
        hostId: hostId,
        participants: [hostId],
      );
      widget.onCreateEvent(newEvent);

      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          content: const Text('Event created successfully!'),
        ),
      );
    } catch (e, stack) {
      messenger?.hideCurrentSnackBar();
      final raw = e.toString().toLowerCase();
      final isRateLimited = raw.contains('5 minute') || raw.contains('wait');
      ErrorHandler.showUserMessage(
        context,
        isRateLimited
            ? AppErrorType.eventCreateRateLimited
            : AppErrorType.eventCreateFailed,
        error: e,
        stackTrace: stack,
        where: 'map_screen._submitCreateEvent',
      );
      return;
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _nextPage() {
    if (_currentPage == 0 && _formModel.title.trim().isEmpty) {
      setState(() => _showValidationErrors = true);
      return;
    }
    if (_currentPage == 1 && _selectedLocation == null) {
      setState(() => _showValidationErrors = true);
      return;
    }
    if (_currentPage == 2) {
      final capacity = int.tryParse(_formModel.expectedAttendeesText.trim());
      if (_selectedStartAtLocal == null || capacity == null || capacity < 2) {
        setState(() => _showValidationErrors = true);
        return;
      }
    }
    FocusScope.of(context).unfocus();
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _prevPage() {
    FocusScope.of(context).unfocus();
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  static const List<String> _stepTitles = ['About', 'Location', 'Details', 'Preview'];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenH = MediaQuery.of(context).size.height;
    final topSafe = MediaQuery.of(context).padding.top;
    final desired = screenH * 0.74;
    final maxH = screenH - bottomInset - topSafe - 8;
    final sheetH = desired < maxH ? desired : maxH;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: sheetH,
        decoration: BoxDecoration(
          color: _sheetBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _sheetHandleColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Header: step title + progress dots + close
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    _stepTitles[_currentPage],
                    style: TextStyle(
                      color: _sheetTitleColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Step ${_currentPage + 1} of $_totalPages',
                    style: TextStyle(color: _sheetMutedColor, fontSize: 12),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _isSubmitting ? null : () => Navigator.pop(context),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _closeButtonBackground,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close,
                          color: _closeButtonIconColor, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: List.generate(_totalPages, (i) {
                  final active = i <= _currentPage;
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: i < _totalPages - 1 ? 6 : 0),
                      height: 4,
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFF3B82F6)
                            : (_isDarkTheme
                                ? Colors.white.withAlpha(24)
                                : Colors.black.withAlpha(18)),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _buildPageAbout(),
                  _buildPageWhere(),
                  _buildPageDetails(),
                  _buildPagePreview(),
                ],
              ),
            ),
            // Footer nav
            _buildWizardFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildWizardFooter() {
    final isLast = _currentPage == _totalPages - 1;
    final canSubmit = _isFormValid && !_isSubmitting;
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: _sheetBackgroundColor,
        border: Border(
          top: BorderSide(
            color: _isDarkTheme
                ? Colors.white.withAlpha(14)
                : Colors.black.withAlpha(10),
          ),
        ),
      ),
      child: Row(
        children: [
          if (_currentPage > 0)
            GestureDetector(
              onTap: _isSubmitting ? null : _prevPage,
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: _visibilityChipBackground,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: _visibilityChipBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_rounded,
                        color: _sheetTitleColor, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'Back',
                      style: TextStyle(
                        color: _sheetTitleColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_currentPage > 0) const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: _isSubmitting
                  ? null
                  : (isLast
                      ? (canSubmit
                          ? _createEvent
                          : () => setState(() => _showValidationErrors = true))
                      : _nextPage),
              child: Opacity(
                opacity: (isLast && !canSubmit) ? 0.55 : 1,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Center(
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isLast ? 'Publish Event' : 'Next',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (!isLast) const SizedBox(width: 6),
                              if (!isLast)
                                const Icon(Icons.arrow_forward_rounded,
                                    color: Colors.white, size: 20),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── PAGE 1: About (emoji avatar + name + description) ──
  Widget _buildPageAbout() {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isDarkTheme
                        ? const Color(0xFF1E2438)
                        : const Color(0xFFF0F2FF),
                    border: Border.all(
                      color: const Color(0xFF3B82F6).withAlpha(60),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: _formModel.selectedEmoji != null &&
                            _formModel.selectedEmoji!.contains('/')
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Image.asset(_formModel.selectedEmoji!,
                                fit: BoxFit.contain),
                          )
                        : Text(_formModel.selectedEmoji ?? '🎉',
                            style: const TextStyle(fontSize: 36)),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Pick an avatar below',
                    style: TextStyle(color: _sheetMutedColor, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 60,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kEventAvatarAssets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final avatarPath = kEventAvatarAssets[index];
                final isSelected = _formModel.selectedEmoji == avatarPath;
                return GestureDetector(
                  onTap: () => setState(() {
                    _formModel =
                        _formModel.copyWith(selectedEmoji: avatarPath);
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? const Color(0xFF3B82F6).withAlpha(35)
                          : _visibilityChipBackground,
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF3B82F6)
                            : _visibilityChipBorder,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Image.asset(avatarPath,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.image_not_supported_outlined,
                              color: Colors.grey,
                              size: 18)),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Text('WHAT DO YOU WANT TO DO?',
              style: TextStyle(
                  color: _sheetMutedColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1)),
          const SizedBox(height: 8),
          _buildTextField(
            _nameController,
            'play some basketball...',
            fieldKey: _nameFieldKey,
            focusNode: _nameFocusNode,
            errorText: _titleError,
            onChanged: (value) => setState(() {
              _formModel = _formModel.copyWith(title: value);
            }),
          ),
          const SizedBox(height: 20),
          _buildLabel('Description (optional)'),
          _buildTextField(
            _descriptionController,
            'what\'s the plan?',
            maxLines: 3,
            fieldKey: _descriptionFieldKey,
            focusNode: _descriptionFocusNode,
            onChanged: (value) => setState(() {
              _formModel = _formModel.copyWith(description: value);
            }),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── PAGE 2: Location (+ tags) ──
  Widget _buildPageWhere() {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel('Where is it happening?'),
          GestureDetector(
            onTap: _openMapLocationPicker,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
              decoration: BoxDecoration(
                color: _inputFieldBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _locationError != null
                      ? const Color(0xFF3B82F6)
                      : _inputFieldBorderColor,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3B82F6).withAlpha(20),
                    blurRadius: 12,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_pin,
                      color: Color(0xFF3B82F6), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selectedLocation == null
                          ? 'Search or tap to set location'
                          : (_selectedLocationName.isNotEmpty
                              ? _selectedLocationName
                              : 'Location selected'),
                      style: TextStyle(
                        color: _selectedLocation == null
                            ? _sheetMutedColor
                            : _sheetTitleColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: _sheetMutedColor, size: 20),
                ],
              ),
            ),
          ),
          _buildInlineError(_locationError),
          const SizedBox(height: 12),
          _buildAestheticToggleTile(
            title: 'Privacy Control',
            subtitle: 'Hide exact location until approved',
            icon: Icons.location_searching_rounded,
            value: _formModel.hideExactLocationUntilApproved,
            onChanged: (value) {
              if (_isSubmitting) return;
              setState(() {
                _formModel = _formModel.copyWith(
                    hideExactLocationUntilApproved: value);
              });
            },
          ),
          const SizedBox(height: 24),
          _buildLabel('Event tags'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _eventTags.map((tag) {
              final isSelected = _formModel.selectedTags.contains(tag);
              return GestureDetector(
                onTap: () => _toggleTag(tag),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF3B82F6).withAlpha(40)
                        : _visibilityChipBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF3B82F6)
                          : _visibilityChipBorder,
                    ),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      color: isSelected
                          ? const Color(0xFF3B82F6)
                          : _sheetMutedColor,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── PAGE 3: Details (members + date + visibility + age + banner) ──
  Widget _buildPageDetails() {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel('How many people?'),
          _buildTextField(
            _peopleCountController,
            'e.g., 50',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            fieldKey: _peopleFieldKey,
            focusNode: _peopleFocusNode,
            errorText: _capacityError,
            onChanged: (value) => setState(() {
              _formModel = _formModel.copyWith(
                expectedAttendeesText: value,
                maxCapacity: int.tryParse(value.trim()) ?? 0,
              );
            }),
          ),
          const SizedBox(height: 20),
          _buildLabel('When?'),
          GestureDetector(
            onTap: _selectDateTime,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _inputFieldBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _timeError != null
                      ? const Color(0xFF3B82F6)
                      : _inputFieldBorderColor,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formModel.timeLabel.isEmpty
                        ? 'Select date & time'
                        : _formModel.timeLabel,
                    style: TextStyle(
                      color: _formModel.timeLabel.isEmpty
                          ? _inputFieldHintColor
                          : _inputFieldTextColor,
                      fontSize: 15,
                    ),
                  ),
                  Icon(Icons.access_time, color: _inputFieldHintColor, size: 20),
                ],
              ),
            ),
          ),
          _buildInlineError(_timeError),
          const SizedBox(height: 20),
          _buildLabel('Meeting Point (optional)'),
          _buildTextField(
            _meetingPointController,
            'e.g. Library Main Gate · Cafe Counter · Metro Gate 2',
            fieldKey: _meetingPointFieldKey,
            focusNode: _meetingPointFocusNode,
            onChanged: (value) => setState(() {
              _formModel = _formModel.copyWith(meetingPoint: value);
            }),
          ),
          const SizedBox(height: 20),
          _buildLabel('Visibility'),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: Text('Public',
                      style: TextStyle(
                        color: _formModel.visibility == 'public'
                            ? _scheme.primary
                            : _sheetMutedColor,
                        fontWeight: FontWeight.w600,
                      )),
                  selected: _formModel.visibility == 'public',
                  showCheckmark: false,
                  selectedColor: _visibilityChipSelectedBackground,
                  backgroundColor: _visibilityChipBackground,
                  side: BorderSide(
                    color: _formModel.visibility == 'public'
                        ? _scheme.primary
                        : _visibilityChipBorder,
                  ),
                  onSelected: (_) => setState(() {
                    _formModel = _formModel.copyWith(visibility: 'public');
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChoiceChip(
                  label: Text('Private',
                      style: TextStyle(
                        color: _formModel.visibility == 'private'
                            ? _scheme.primary
                            : _sheetMutedColor,
                        fontWeight: FontWeight.w600,
                      )),
                  selected: _formModel.visibility == 'private',
                  showCheckmark: false,
                  selectedColor: _visibilityChipSelectedBackground,
                  backgroundColor: _visibilityChipBackground,
                  side: BorderSide(
                    color: _formModel.visibility == 'private'
                        ? _scheme.primary
                        : _visibilityChipBorder,
                  ),
                  onSelected: (_) => setState(() {
                    _formModel = _formModel.copyWith(visibility: 'private');
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildAestheticToggleTile(
            title: 'Join Approval',
            subtitle: _formModel.isApprovalRequired
                ? 'Approval required to join'
                : 'Anyone can join directly',
            icon: Icons.how_to_reg_rounded,
            value: _formModel.isApprovalRequired,
            onChanged: (value) {
              if (_isSubmitting) return;
              setState(() {
                _formModel = _formModel.copyWith(isApprovalRequired: value);
              });
            },
          ),
          const SizedBox(height: 20),
          _buildLabel('Who should join'),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF3B82F6),
              inactiveTrackColor:
                  _isDarkTheme ? Colors.white24 : Colors.black12,
              trackHeight: 4,
              rangeThumbShape:
                  const RoundRangeSliderThumbShape(enabledThumbRadius: 10),
              overlayColor: const Color(0xFF3B82F6).withAlpha(40),
            ),
            child: RangeSlider(
              values: _ageRange,
              min: 15,
              max: 100,
              divisions: 85,
              labels: RangeLabels(
                _ageRange.start.round().toString(),
                _ageRange.end.round().toString(),
              ),
              onChanged: (values) => setState(() => _ageRange = values),
            ),
          ),
          Text(
            '${_ageRange.start.round()} - ${_ageRange.end.round()} years',
            style: TextStyle(
                color: _sheetMutedColor,
                fontSize: 14,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 20),
          _buildLabel('Banner (optional)'),
          GestureDetector(
            onTap: _pickBannerImage,
            child: Container(
              width: double.infinity,
              height: 92,
              decoration: BoxDecoration(
                color: _visibilityChipBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _visibilityChipBorder),
              ),
              child: _formModel.bannerImagePath == null
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.image_outlined,
                            color: _sheetMutedColor, size: 22),
                        const SizedBox(width: 8),
                        Text('Add banner',
                            style: TextStyle(
                                color: _sheetMutedColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w500)),
                      ],
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(File(_formModel.bannerImagePath!),
                              fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _formModel = _formModel.copyWith(
                                  clearBannerImagePath: true);
                            }),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(130),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close,
                                  color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }


  // ── Quality Score ──
  int _calcQualityScore() {
    int score = 0;
    if (_formModel.title.trim().isNotEmpty) score += 20;
    if (_formModel.description.trim().isNotEmpty) score += 20;
    if (_selectedStartAtLocal != null) score += 15;
    if (_selectedLocation != null) score += 15;
    if (_formModel.meetingPoint.trim().isNotEmpty) score += 10;
    final banner = _formModel.bannerImagePath;
    if (banner != null && banner.trim().isNotEmpty) score += 20;
    return score;
  }

  String _qualityLabel(int score) {
    if (score >= 90) return 'Ready to publish';
    if (score >= 70) return 'Looking good';
    if (score >= 40) return 'Good start';
    return 'Needs more detail';
  }

  Color _qualityColor(int score) {
    if (score >= 90) return const Color(0xFF34D399);
    if (score >= 70) return const Color(0xFF60A5FA);
    if (score >= 40) return const Color(0xFFFBBF24);
    return const Color(0xFF94A3B8);
  }

  // ── PAGE 4: Preview ──
  Widget _buildPagePreview() {
    final score = _calcQualityScore();
    final label = _qualityLabel(score);
    final scoreColor = _qualityColor(score);
    final hasBanner = _formModel.bannerImagePath != null &&
        _formModel.bannerImagePath!.trim().isNotEmpty;
    final tagColor = _colorFromTags();
    final avatarPath = _formModel.selectedEmoji ?? _avatarFromTags();

    // Gather improvement suggestions
    final improvements = <String>[];
    if (_formModel.description.trim().isEmpty) {
      improvements.add('Add a description so people know what to expect');
    }
    if (_formModel.meetingPoint.trim().isEmpty) {
      improvements.add('Add a meeting point so attendees know where to gather');
    }
    if (!hasBanner) {
      improvements.add('Add a cover image — landscape, 16:9 format (+20 points)');
    }

    return SingleChildScrollView(
      controller: _formScrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Quality Score card ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isDarkTheme
                  ? const Color(0xFF171D2A)
                  : _scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: scoreColor.withAlpha(60),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Event Quality',
                            style: TextStyle(
                              color: _sheetMutedColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '$score',
                                style: TextStyle(
                                  color: scoreColor,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                ),
                              ),
                              Text(
                                ' / 100',
                                style: TextStyle(
                                  color: _sheetMutedColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: scoreColor.withAlpha(30),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: scoreColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: score / 100,
                    minHeight: 6,
                    backgroundColor: _isDarkTheme
                        ? Colors.white.withAlpha(18)
                        : Colors.black.withAlpha(10),
                    valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                  ),
                ),
              ],
            ),
          ),

          // ── Recommendations ──
          if (improvements.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'IMPROVEMENTS',
              style: TextStyle(
                color: _sheetMutedColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: _isDarkTheme
                    ? const Color(0xFF171D2A)
                    : _scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _visibilityChipBorder),
              ),
              child: Column(
                children: improvements.asMap().entries.map((entry) {
                  final isLast = entry.key == improvements.length - 1;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11),
                        child: Row(
                          children: [
                            Icon(
                              Icons.add_circle_outline_rounded,
                              size: 16,
                              color: _sheetMutedColor,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                entry.value,
                                style: TextStyle(
                                  color: _sheetMutedColor,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isLast)
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: _visibilityChipBorder,
                          indent: 14,
                          endIndent: 14,
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: 20),
          Text(
            'PREVIEW',
            style: TextStyle(
              color: _sheetMutedColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),

          // ── Event preview card ──
          Container(
            decoration: BoxDecoration(
              color: _isDarkTheme
                  ? const Color(0xFF131A27)
                  : _scheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _visibilityChipBorder),
            ),
            clipBehavior: Clip.hardEdge,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Banner
                _buildPreviewBanner(
                    hasBanner: hasBanner,
                    tagColor: tagColor,
                    avatarPath: avatarPath),

                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        _formModel.title.trim().isEmpty
                            ? 'Event name'
                            : _formModel.title.trim(),
                        style: TextStyle(
                          color: _formModel.title.trim().isEmpty
                              ? _sheetMutedColor
                              : _sheetTitleColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_formModel.selectedTags.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _formModel.selectedTags.map((tag) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6).withAlpha(28),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                tag,
                                style: const TextStyle(
                                  color: Color(0xFF60A5FA),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 14),
                      // Date
                      _buildPreviewInfoRow(
                        icon: Icons.calendar_today_outlined,
                        text: _selectedStartAtLocal == null
                            ? 'Date not set'
                            : DateFormat('EEE, MMM d • h:mm a')
                                .format(_selectedStartAtLocal!),
                        muted: _selectedStartAtLocal == null,
                      ),
                      const SizedBox(height: 10),
                      // Location
                      _buildPreviewInfoRow(
                        icon: Icons.location_on_outlined,
                        text: _selectedLocation == null
                            ? 'Location not set'
                            : (_selectedLocationName.isNotEmpty
                                ? _selectedLocationName
                                : 'Location selected'),
                        muted: _selectedLocation == null,
                      ),
                      // Meeting point
                      if (_formModel.meetingPoint.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _isDarkTheme
                                ? Colors.white.withAlpha(8)
                                : Colors.black.withAlpha(5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'MEETING POINT',
                                style: TextStyle(
                                  color: _sheetMutedColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formModel.meetingPoint.trim(),
                                style: TextStyle(
                                  color: _sheetTitleColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // Description
                      if (_formModel.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Divider(
                          height: 1,
                          color: _visibilityChipBorder,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'About',
                          style: TextStyle(
                            color: _sheetTitleColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _formModel.description.trim(),
                          style: TextStyle(
                            color: _sheetMutedColor,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Cover image upload prompt (if no cover)
          if (!hasBanner) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _pickBannerImage,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: _isDarkTheme
                      ? const Color(0xFF171D2A)
                      : _scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF3B82F6).withAlpha(80)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.add_photo_alternate_outlined,
                        color: Color(0xFF3B82F6), size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add a cover image',
                            style: TextStyle(
                              color: _sheetTitleColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Landscape image, 16:9 format  •  +20 quality points',
                            style: TextStyle(
                              color: _sheetMutedColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: _sheetMutedColor, size: 20),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildPreviewBanner({
    required bool hasBanner,
    required Color tagColor,
    required String avatarPath,
  }) {
    const bannerHeight = 160.0;

    if (hasBanner) {
      return Stack(
        children: [
          SizedBox(
            height: bannerHeight,
            width: double.infinity,
            child: Image.file(
              File(_formModel.bannerImagePath!),
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => setState(
                  () => _formModel = _formModel.copyWith(clearBannerImagePath: true)),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(130),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      );
    }

    // Auto fallback: gradient based on category color
    return Container(
      height: bannerHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tagColor.withAlpha(180),
            tagColor.withAlpha(80),
          ],
        ),
      ),
      child: Center(
        child: avatarPath.contains('/')
            ? Image.asset(avatarPath,
                width: 56, height: 56, fit: BoxFit.contain)
            : Text(avatarPath,
                style: const TextStyle(fontSize: 48)),
      ),
    );
  }

  Widget _buildPreviewInfoRow({
    required IconData icon,
    required String text,
    bool muted = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 17,
          color: muted ? _sheetMutedColor.withAlpha(120) : _sheetMutedColor,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: muted
                  ? _sheetMutedColor.withAlpha(120)
                  : _sheetTitleColor,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInlineError(String? error) {
    if (error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Text(
        error,
        style: const TextStyle(
          color: Color(0xFF3B82F6),
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildAestheticToggleTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color:
            _isDarkTheme ? const Color(0xFF171D2A) : _visibilityChipBackground,
        border: Border.all(
          color: value
              ? const Color(0xFF3B82F6).withAlpha(170)
              : _visibilityChipBorder,
        ),
        boxShadow: value
            ? [
                BoxShadow(
                  color: const Color(0xFF3B82F6).withAlpha(35),
                  blurRadius: 14,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value
                  ? const Color(0xFF3B82F6).withAlpha(35)
                  : (_isDarkTheme
                      ? Colors.white.withAlpha(12)
                      : Colors.black.withAlpha(8)),
            ),
            child: Icon(
              icon,
              size: 17,
              color: value
                  ? const Color(0xFF7FB3FF)
                  : (_isDarkTheme ? Colors.white70 : Colors.black54),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _sheetTitleColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: _sheetMutedColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: const Color(0xFF3B82F6).withAlpha(130),
            activeColor: const Color(0xFF3B82F6),
            inactiveTrackColor:
                _isDarkTheme ? Colors.white.withAlpha(28) : Colors.black12,
            onChanged: _isSubmitting ? null : onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: _sheetTitleColor,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
    FocusNode? focusNode,
    GlobalKey? fieldKey,
    String? errorText,
  }) {
    return Container(
      key: fieldKey,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        style: TextStyle(color: _inputFieldTextColor, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: _inputFieldHintColor),
          filled: true,
          fillColor: _inputFieldBackground,
          errorText: errorText,
          errorStyle: const TextStyle(color: Color(0xFF3B82F6), fontSize: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _inputFieldBorderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _inputFieldBorderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF3B82F6)),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}

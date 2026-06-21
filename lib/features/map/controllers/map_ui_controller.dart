// ignore_for_file: invalid_use_of_protected_member

part of '../../../screens/map_screen.dart';

extension _MapUiController on _MapScreenState {
  void _setStateFromMap(VoidCallback callback) {
    if (!mounted) return;
    print('SETSTATE CALLED');
    setState(callback);
  }

  HomeTab _tabFromIndex(int index) {
    switch (index) {
      case 1:
        return HomeTab.explore;
      case 2:
        return HomeTab.chat;
      case 3:
        return HomeTab.profile;
      case 0:
      default:
        return HomeTab.map;
    }
  }

  void _syncActiveTabProviderFromIndex(int index) {
    ref.read(activeTabProvider.notifier).state = _tabFromIndex(index);
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const FilterBottomSheet(),
    );
  }

  void _showThemeSheet() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final surface = scheme.surface;
    final onSurface = scheme.onSurface;
    final currentMode = AppThemeService.instance.currentMode;

    Future<void> applyMode(ThemeMode mode) async {
      await AppThemeService.instance.setThemeMode(mode);
      if (mounted) Navigator.pop(context);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(YanegiSpacing.lg),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(YanegiRadius.xl),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose theme',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: YanegiSpacing.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                textColor: onSurface,
                iconColor: onSurface,
                leading: const Icon(Icons.phone_android_rounded),
                title: const Text('System'),
                trailing: currentMode == ThemeMode.system
                    ? const Icon(Icons.check_rounded,
                        color: YanegiColors.primary)
                    : null,
                onTap: () => applyMode(ThemeMode.system),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                textColor: onSurface,
                iconColor: onSurface,
                leading: const Icon(Icons.light_mode_rounded),
                title: const Text('Light'),
                trailing: currentMode == ThemeMode.light
                    ? const Icon(Icons.check_rounded,
                        color: YanegiColors.primary)
                    : null,
                onTap: () => applyMode(ThemeMode.light),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                textColor: onSurface,
                iconColor: onSurface,
                leading: const Icon(Icons.dark_mode_rounded),
                title: const Text('Dark'),
                trailing: currentMode == ThemeMode.dark
                    ? const Icon(Icons.check_rounded,
                        color: YanegiColors.primary)
                    : null,
                onTap: () => applyMode(ThemeMode.dark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          height: 44,
          padding: const EdgeInsets.only(left: 12, right: 2),
          decoration: BoxDecoration(
            color: _searchBarColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
                color: Colors.transparent, width: 0),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: _searchBarIconColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search...',
                    hintStyle:
                        TextStyle(color: _searchBarHintColor, fontSize: 15),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  textAlignVertical: TextAlignVertical.center,
                  style: TextStyle(color: _searchBarIconColor, fontSize: 15),
                  onChanged: (val) {
                    if (_debounce?.isActive ?? false) _debounce!.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () {
                      ref
                          .read(filterProvider.notifier)
                          .updateFilters(searchQuery: val);
                    });
                  },
                ),
              ),
              Container(
                width: 1,
                height: 20,
                color: Colors.white.withAlpha(32),
              ),
              Consumer(builder: (context, ref, child) {
                final hasFilters = ref.watch(filterProvider).hasActiveFilters();
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: _showFilterSheet,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: Stack(
                          children: [
                            Icon(Icons.filter_list_rounded,
                                color: _searchBarIconColor, size: 20),
                            if (hasFilters)
                              Positioned(
                                top: 0,
                                right: 0,
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF3B82F6),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopActionsGroup() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: _topActionButtonColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _topActionBorderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<int>(
            stream: _notifCountStream,
            builder: (context, snapshot) {
              final unreadCount = snapshot.data ?? 0;
              return _buildActionPillButton(
                icon: Icons.notifications_outlined,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ActivityScreen()),
                ),
                badgeText: unreadCount > 0
                    ? (unreadCount > 9 ? '9+' : '$unreadCount')
                    : null,
              );
            },
          ),
          _buildActionPillButton(
            icon: Icons.my_location_rounded,
            onTap: () async {
              final userLocation = await _ensureUserLocation(
                moveMap: false,
                showErrors: true,
              );
              if (userLocation != null) {
                _animateToLocation(userLocation, zoom: 14);
              }
            },
          ),
          _buildActionPillButton(
            icon: AppThemeService.instance.currentMode == ThemeMode.system
                ? Icons.phone_android_rounded
                : (_isDarkTheme
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded),
            onTap: _showThemeSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildActionPillButton({
    required IconData icon,
    required VoidCallback onTap,
    String? badgeText,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(icon, color: _topActionIconColor, size: 20),
            if (badgeText != null)
              Positioned(
                right: 1,
                top: 1,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5F8FD9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 16),
                  child: Text(
                    badgeText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: YanegiTypeScale.meta,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _topActionButtonColor,
        shape: BoxShape.circle,
        border: Border.all(color: _topActionBorderColor, width: 1),
      ),
      child: Icon(icon, color: _topActionIconColor, size: 20),
    );
  }

  Widget _buildThemeButton() {
    return GestureDetector(
      onTap: _showThemeSheet,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _topActionButtonColor,
          shape: BoxShape.circle,
          border: Border.all(color: _topActionBorderColor, width: 1),
        ),
        child: Icon(
          AppThemeService.instance.currentMode == ThemeMode.system
              ? Icons.phone_android_rounded
              : (_isDarkTheme
                  ? Icons.dark_mode_rounded
                  : Icons.light_mode_rounded),
          color: _topActionIconColor,
          size: 19,
        ),
      ),
    );
  }

  Widget _buildRecenterButton() {
    return GestureDetector(
      onTap: () async {
        final userLocation = await _ensureUserLocation(
          moveMap: false,
          showErrors: true,
        );
        if (userLocation != null) {
          _animateToLocation(userLocation, zoom: 14);
        }
      },
      child: _buildIconButton(Icons.my_location_rounded),
    );
  }

  Widget _buildMinimalBottomNav() {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      margin: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        8 + (bottomPadding > 0 ? bottomPadding : 12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        color: _taskbarColor,
        border: Border.all(color: _taskbarBorderColor, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavItem(Icons.home_rounded, 'Home', 0),
          _buildNavItem(Icons.explore_rounded, 'Explore', 1),
          _buildCenterAddButton(),
          _buildChatsNavItem(),
          _buildNavItem(Icons.person_rounded, 'Profile', 3),
        ],
      ),
    );
  }

  Widget _buildCenterAddButton() {
    return GestureDetector(
      onTap: _handleOrbTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF3B82F6),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3B82F6).withOpacity(0.45),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 26),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isActive = _navIndex == index;

    return GestureDetector(
      onTap: () {
        if (!mounted) return;
        if (_navIndex == index) return;
        setState(() {
          if (index == 3 && _navIndex != 3) {
            _previousTabIndexBeforeProfile = _navIndex;
          }
          _navIndex = index;
        });
        if (!mounted) return;
        _syncActiveTabProviderFromIndex(index);
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 44,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive
                  ? _taskbarIconActiveColor
                  : _taskbarIconInactiveColor.withAlpha(180),
              size: 24,
            ),
            const SizedBox(height: 3),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: isActive ? 1 : 0,
              child: Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: Color(0xFF3B82F6),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatsNavItem() {
    return StreamBuilder<int>(
      stream: _chatUnreadCountStream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        final isActive = _navIndex == 2;
        return GestureDetector(
          onTap: () {
            if (!mounted) return;
            if (_navIndex == 2) return;
            setState(() => _navIndex = 2);
            if (!mounted) return;
            _syncActiveTabProviderFromIndex(2);
          },
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 44,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.chat_bubble_rounded,
                      color: isActive
                          ? _taskbarIconActiveColor
                          : _taskbarIconInactiveColor.withAlpha(180),
                      size: 24,
                    ),
                    if (count > 0)
                      Positioned(
                        top: -5,
                        right: -7,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutBack,
                          builder: (_, scale, child) =>
                              Transform.scale(scale: scale, child: child),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1.5),
                            constraints: const BoxConstraints(minWidth: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE53935),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              count > 99 ? '99+' : '$count',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: isActive ? 1 : 0,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3B82F6),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

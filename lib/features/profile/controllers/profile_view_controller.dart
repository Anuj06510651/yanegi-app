// ignore_for_file: invalid_use_of_protected_member

part of '../../../screens/profile_social_screen.dart';

extension _ProfileViewController on _SocialProfileScreenState {
  Widget _buildBlockedProfileView({
    required bool blockedByMe,
    required bool blockedByThem,
  }) {
    final subtitle = blockedByMe
        ? 'You blocked this user. Unblock them to interact again.'
        : blockedByThem
            ? 'This user is not available right now.'
            : 'This user is not available.';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildTopBar(),
          ),
          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: YanegiColors.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  const Icon(Icons.lock_person_rounded,
                      color: Colors.white70, size: 34),
                  const SizedBox(height: 12),
                  const Text(
                    'User not available',
                    style: TextStyle(
                      color: YanegiColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: YanegiColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileLoadingState() {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  Widget _buildProfileErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.redAccent, size: 36),
            const SizedBox(height: 10),
            const Text(
              'Could not load profile right now.',
              textAlign: TextAlign.center,
              style: TextStyle(color: YanegiColors.textPrimary, fontSize: 14),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _loadProfileData,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuestSignInPage() {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: YanegiColors.primary.withAlpha(25),
                  ),
                  child: Icon(
                    Icons.person_outline_rounded,
                    color: YanegiColors.primary,
                    size: 44,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Sign in to access your profile',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _textPrimaryColor,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Create a free account to set up your profile, '
                  'join events, and connect with people.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _textSecondaryColor,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AuthLandingPage(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: YanegiColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Sign in / Create account',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: _textPrimaryColor,
            size: 20,
          ),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
              return;
            }

            widget.onBackPressed?.call();
          },
        ),
        Expanded(
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _username.isNotEmpty ? _username : (_isOwnProfile ? 'My Profile' : _displayName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _textPrimaryColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
                if (_isVerified) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.verified_rounded,
                      color: YanegiColors.primary, size: 16),
                ],
              ],
            ),
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.more_vert_rounded,
            color: _textPrimaryColor,
            size: 20,
          ),
          onPressed: _isOwnProfile
              ? _showOwnProfileActionSheet
              : _showProfileActionSheet,
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        _bio,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.left,
        style: TextStyle(
          color: _textSecondaryColor.withAlpha(220),
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _glassButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    required bool filled,
    bool solidPrimary = false,
    bool busy = false,
  }) {
    final contentColor =
        onTap == null ? _textSecondaryColor : _textPrimaryColor;
    return InkWell(
      onTap: (_isActionBusy || busy) ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: solidPrimary
              ? YanegiColors.primary
              : filled
                  ? YanegiColors.primary.withAlpha(28)
                  : _surfaceColor.withAlpha(190),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: solidPrimary
                ? YanegiColors.primary
                : filled
                    ? YanegiColors.primary.withAlpha(120)
                    : _textSecondaryColor.withAlpha(55),
            width: solidPrimary ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(contentColor),
                ),
              )
            else
              Icon(icon, size: solidPrimary ? 18 : 16, color: contentColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: contentColor,
                fontWeight: FontWeight.w700,
                fontSize: solidPrimary ? 15 : 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

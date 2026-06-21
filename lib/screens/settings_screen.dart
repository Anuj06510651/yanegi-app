import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:yanegi/onboarding/auth_bootstrapper.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_theme_service.dart';
import '../services/chat_peer_cache.dart';
import '../services/local_profile_cache.dart';
import '../services/user_service.dart';
import '../theme/yanegi_theme.dart';
import 'blocked_users_screen.dart';
import 'community_guidelines_screen.dart';
import 'event_request_history_screen.dart';
import 'faq_screen.dart';
import 'location_usage_explanation_screen.dart';
import 'privacy_policy_screen.dart';
import 'profile_edit_screen.dart';
import 'report_problem_screen.dart';
import 'saved_events_screen.dart';
import 'safety_reporting_screen.dart';
import 'send_feedback_screen.dart';
import 'terms_of_service_screen.dart';

import '../chat/providers/chat_providers.dart';
import '../providers/explore_feed_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final UserService _userService = UserService();
  final AppThemeService _themeService = AppThemeService.instance;

  bool _profileVisible = true;
  bool _isUpdatingVisibility = false;
  bool _pushMaster = true;
  bool _isUpdatingPushMaster = false;
  bool _eventReminders = true;
  bool _nearbyEvents = true;
  bool _chatMessages = true;
  bool _marketing = false;
  bool _nearbyActivity = true;
  bool _isUpdatingNearbyActivity = false;
  bool _showInEvents = true;
  bool _isUpdatingShowInEvents = false;
  bool _isProcessingAccountAction = false;
  String _whoCanMessage = 'Everyone';
  String _theme = 'System';
  String _currentEmail = '';
  String _currentPhone = '';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSubscription;
  VoidCallback? _themeListener;

  ColorScheme get _scheme => Theme.of(context).colorScheme;
  Color get _bg => Theme.of(context).scaffoldBackgroundColor;
  Color get _surface => _scheme.surface;
  Color get _textPrimary => _scheme.onSurface;
  Color get _textSecondary => _scheme.onSurface.withOpacity(0.68);
  Color get _linkBlue => const Color(0xFF5F8FD9);

  @override
  void initState() {
    super.initState();
    _theme = _themeService.currentLabel;
    _themeListener = () {
      if (!mounted) return;
      setState(() => _theme = _themeService.currentLabel);
    };
    _themeService.themeModeListenable.addListener(_themeListener!);
    unawaited(_themeService.loadThemePreference());
    _bindUserRealtime();
  }

  void _bindUserRealtime() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    _userSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
      final data = doc.data() ?? const <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _profileVisible = (data['profileVisibility'] ?? true) == true;
        // Prefer the Yanegi-stored email over the auth credential so the
        // Settings screen reads from the canonical app profile, not the
        // Google identity. Both values match for users created via Google
        // sign-in, but reading from the user doc keeps the surface aligned
        // with the rest of the app.
        _currentEmail =
            (data['email'] ?? FirebaseAuth.instance.currentUser?.email ?? '')
                .toString();
        _currentPhone = (FirebaseAuth.instance.currentUser?.phoneNumber ??
                data['phone'] ??
                '')
            .toString();
      });
    });

    _loadPushNotificationSetting();
    _loadDiscoveryPrivacySettings();
  }

  Future<void> _loadPushNotificationSetting() async {
    try {
      final enabled = await _userService.getPushNotificationsEnabled();
      if (!mounted) return;
      setState(() => _pushMaster = enabled);
    } catch (_) {
      // Keep default and avoid interrupting Settings UI.
    }
  }

  Future<void> _loadDiscoveryPrivacySettings() async {
    try {
      final nearbyEnabled = await _userService.getNearbyActivityEnabled();
      final showInEventsEnabled =
          await _userService.getShowProfileInEventsEnabled();
      if (!mounted) return;
      setState(() {
        _nearbyActivity = nearbyEnabled;
        _showInEvents = showInEventsEnabled;
      });
    } catch (_) {
      // Keep defaults without blocking settings screen.
    }
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    if (_themeListener != null) {
      _themeService.themeModeListenable.removeListener(_themeListener!);
    }
    super.dispose();
  }

  Future<void> _openEditProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    final snap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!mounted) return;
    final data = snap.data() ?? const <String, dynamic>{};
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileEditScreen(
          initialName: (data['name'] ?? data['displayName'] ?? '').toString(),
          initialUsername: ((data['username'] ?? '') as String).startsWith('@')
              ? (data['username'] ?? '').toString()
              : '@${(data['username'] ?? '').toString()}',
          initialBio: (data['bio'] ?? '').toString(),
        ),
      ),
    );
    if (!mounted) return;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: IconThemeData(color: _textPrimary),
        title: Text(
          'Settings',
          style: TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: YanegiTypeScale.h2,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _section('ACCOUNT'),
          _card([
            _nav(Icons.person_outline, 'Edit Profile', onTap: _openEditProfile),
            _divider(),
            _nav(Icons.mail_outline, 'Change Phone/Email',
                onTap: _openChangeContact),
            _divider(),
            _toggle(
              Icons.visibility_outlined,
              'Profile Visibility',
              _profileVisible,
              _isUpdatingVisibility ? null : _setProfileVisibility,
            ),
          ]),
          _gap(),
          _section('NOTIFICATIONS'),
          _card([
            _toggle(
              Icons.notifications_active_outlined,
              'Push Notifications',
              _pushMaster,
              _isUpdatingPushMaster ? null : _setPushMaster,
            ),
            _divider(),
            _toggle(
                Icons.event_note_outlined,
                'Event Reminders',
                _eventReminders,
                _pushMaster
                    ? (v) => setState(() => _eventReminders = v)
                    : null),
            _divider(),
            _toggle(Icons.near_me_outlined, 'Nearby Events', _nearbyEvents,
                _pushMaster ? (v) => setState(() => _nearbyEvents = v) : null),
            _divider(),
            _toggle(Icons.chat_bubble_outline, 'Chat Messages', _chatMessages,
                _pushMaster ? (v) => setState(() => _chatMessages = v) : null),
            _divider(),
            _toggle(
                Icons.campaign_outlined,
                'Marketing Notifications',
                _marketing,
                _pushMaster ? (v) => setState(() => _marketing = v) : null),
          ]),
          _gap(),
          _section('DISCOVERY & PRIVACY'),
          _card([
            _toggle(
                Icons.location_on_outlined,
                'Nearby Activity',
                _nearbyActivity,
                _isUpdatingNearbyActivity ? null : _setNearbyActivity),
            _divider(),
            _nav(Icons.info_outline, 'Location Usage Explanation',
                onTap: _openLocationUsageExplanation),
            _divider(),
            _value(Icons.alternate_email, 'Who Can Message Me', _whoCanMessage,
                onTap: _pickMessagePrivacy),
            _divider(),
            _toggle(
                Icons.badge_outlined,
                'Show Profile in Events',
                _showInEvents,
                _isUpdatingShowInEvents ? null : _setShowProfileInEvents),
          ]),
          _gap(),
          _section('SOCIAL'),
          _card([
            _nav(Icons.bookmark_outline_rounded, 'Saved Events',
                onTap: _openSavedEvents),
            _divider(),
            _nav(Icons.block_outlined, 'Blocked Users',
                onTap: _openBlockedUsers),
            _divider(),
            _nav(Icons.send_outlined, 'Sent/Received Event Requests',
                onTap: _openEventRequestHistory),
          ]),
          _gap(),
          _section('APP PREFERENCES'),
          _card([
            _value(Icons.dark_mode_outlined, 'Theme', _theme,
                onTap: _pickTheme),
          ]),
          _gap(),
          _section('CREATOR MODE'),
          _card([
            _nav(Icons.verified_outlined, 'Become a Host/Partner',
                onTap: _openCreatorEarningsPreview),
          ]),
          _gap(),
          _section('FEEDBACK & SUPPORT'),
          _card([
            _nav(Icons.star_outline, 'Rate App',
                onTap: () => _toast('Coming soon')),
            _divider(),
            _nav(Icons.feedback_outlined, 'Send Feedback',
                onTap: _openSendFeedback),
            _divider(),
            _nav(Icons.report_gmailerrorred_outlined, 'Report a Problem',
                onTap: _openReportProblem),
            _divider(),
            _nav(Icons.support_agent_outlined, 'Contact Support',
                onTap: _contactSupport),
            _divider(),
            _nav(Icons.help_outline, 'FAQ', onTap: _openFaq),
          ]),
          _gap(),
          _section('LEGAL'),
          _card([
            _nav(Icons.privacy_tip_outlined, 'Privacy Policy',
                onTap: _openPrivacyPolicy),
            _divider(),
            _nav(Icons.description_outlined, 'Terms & Conditions',
                onTap: _openTermsOfService),
            _divider(),
            _nav(Icons.gavel_outlined, 'Community Guidelines',
                onTap: _openCommunityGuidelines),
            _divider(),
            _nav(Icons.shield_outlined, 'Safety & Reporting Policy',
                onTap: _openSafetyReporting),
          ]),
          _gap(),
          _section('ACCOUNT ACTIONS', danger: true),
          _card([
            _nav(Icons.pause_circle_outline, 'Deactivate Account',
                danger: true, onTap: _confirmDeactivate),
            _divider(),
            _nav(Icons.delete_forever_outlined, 'Delete Account',
                danger: true, onTap: _confirmDelete),
            _divider(),
            _nav(Icons.logout, 'Sign Out', danger: true, onTap: _signOut),
          ]),
        ],
      ),
    );
  }

  Widget _section(String title, {bool danger = false}) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          title,
          style: TextStyle(
            color: danger ? Colors.red.shade400 : _textSecondary,
            fontSize: YanegiTypeScale.label,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _card(List<Widget> children) => Container(
        color: Colors.transparent,
        child: Column(children: children),
      );

  Widget _divider() => const SizedBox.shrink();

  Widget _gap() => const SizedBox(height: 16);

  Widget _nav(IconData icon, String title,
      {required VoidCallback onTap, bool danger = false}) {
    final color = danger ? Colors.red.shade400 : _textPrimary;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      minLeadingWidth: 30,
      leading: Icon(icon, color: color, size: 22),
      title: Text(title,
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.w500,
              fontSize: YanegiTypeScale.body)),
      trailing:
          Icon(Icons.chevron_right, color: _textSecondary.withOpacity(0.75)),
      onTap: onTap,
    );
  }

  Widget _toggle(
      IconData icon, String title, bool value, ValueChanged<bool>? onChanged) {
    final enabled = onChanged != null;
    final iconTint = enabled
        ? (value ? YanegiColors.primary : _textPrimary.withOpacity(0.9))
        : _textSecondary.withOpacity(0.6);
    final titleColor = enabled ? _textPrimary : _textSecondary.withOpacity(0.8);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      minLeadingWidth: 30,
      leading: Icon(icon, color: iconTint, size: 22),
      title: Text(
        title,
        style: TextStyle(
          color: titleColor,
          fontWeight: FontWeight.w500,
          fontSize: YanegiTypeScale.body,
        ),
      ),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeColor: YanegiColors.primary,
        activeTrackColor: YanegiColors.primary.withOpacity(0.45),
        inactiveThumbColor: _surface,
        inactiveTrackColor: _textSecondary.withOpacity(0.28),
      ),
      onTap: enabled ? () => onChanged(!value) : null,
    );
  }

  Widget _value(IconData icon, String title, String value,
      {required VoidCallback onTap}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      minLeadingWidth: 30,
      leading: Icon(icon, color: _textPrimary, size: 22),
      title: Text(title,
          style: TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w500,
              fontSize: YanegiTypeScale.body)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  color: _textSecondary, fontSize: YanegiTypeScale.label)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: _textSecondary.withOpacity(0.75)),
        ],
      ),
      onTap: onTap,
    );
  }

  Future<void> _pickTheme() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _surface,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _sheetOption('System'),
          _sheetOption('Light'),
          _sheetOption('Dark'),
        ]),
      ),
    );
    if (choice == null) return;

    final previous = _theme;
    setState(() => _theme = choice);
    try {
      await _themeService.setThemeLabel(choice);
    } catch (_) {
      if (!mounted) return;
      setState(() => _theme = previous);
      _toast('Could not update theme. Please try again.');
    }
  }

  Future<void> _pickMessagePrivacy() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _surface,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _sheetOption('Everyone'),
          _sheetOption('Attendees and friends only'),
          _sheetOption('Friends Only'),
        ]),
      ),
    );
    if (choice != null) setState(() => _whoCanMessage = choice);
  }

  Widget _sheetOption(String value) {
    return ListTile(
      title: Text(value, style: TextStyle(color: _textPrimary)),
      onTap: () => Navigator.pop(context, value),
    );
  }

  Future<void> _setProfileVisibility(bool value) async {
    final previous = _profileVisible;
    setState(() {
      _profileVisible = value;
      _isUpdatingVisibility = true;
    });

    try {
      await _userService.updateProfileVisibility(isVisible: value);
      if (!mounted) return;
      _toast(value
          ? 'Your profile is now visible in search and suggestions.'
          : 'Your profile is now hidden from search and suggestions.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _profileVisible = previous);
      _toast('Could not update profile visibility. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isUpdatingVisibility = false);
      }
    }
  }

  Future<void> _setPushMaster(bool value) async {
    final previous = _pushMaster;
    setState(() {
      _pushMaster = value;
      _isUpdatingPushMaster = true;
    });

    try {
      await _userService.setPushNotificationsEnabled(value);
    } catch (_) {
      if (!mounted) return;
      setState(() => _pushMaster = previous);
      _toast('Could not update push notification setting. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isUpdatingPushMaster = false);
      }
    }
  }

  Future<void> _setNearbyActivity(bool value) async {
    final previous = _nearbyActivity;
    setState(() {
      _nearbyActivity = value;
      _isUpdatingNearbyActivity = true;
    });

    try {
      await _userService.setNearbyActivityEnabled(value);
    } catch (_) {
      if (!mounted) return;
      setState(() => _nearbyActivity = previous);
      _toast('Could not update nearby activity setting. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isUpdatingNearbyActivity = false);
      }
    }
  }

  Future<void> _setShowProfileInEvents(bool value) async {
    final previous = _showInEvents;
    setState(() {
      _showInEvents = value;
      _isUpdatingShowInEvents = true;
    });

    try {
      await _userService.setShowProfileInEventsEnabled(value);
    } catch (_) {
      if (!mounted) return;
      setState(() => _showInEvents = previous);
      _toast(
          'Could not update profile visibility in events. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isUpdatingShowInEvents = false);
      }
    }
  }

  Future<void> _openLocationUsageExplanation() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LocationUsageExplanationScreen(),
      ),
    );
  }

  Future<void> _openSavedEvents() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SavedEventsScreen(),
      ),
    );
  }

  Future<void> _openBlockedUsers() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const BlockedUsersScreen(),
      ),
    );
  }

  Future<void> _openEventRequestHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const EventRequestHistoryScreen(),
      ),
    );
  }

  Future<void> _openSendFeedback() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SendFeedbackScreen(),
      ),
    );
  }

  Future<void> _openReportProblem() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ReportProblemScreen(),
      ),
    );
  }

  Future<void> _openFaq() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const FAQScreen(),
      ),
    );
  }

  Future<void> _openPrivacyPolicy() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PrivacyPolicyScreen(),
      ),
    );
  }

  Future<void> _openTermsOfService() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const TermsOfServiceScreen(),
      ),
    );
  }

  Future<void> _openCommunityGuidelines() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CommunityGuidelinesScreen(),
      ),
    );
  }

  Future<void> _openSafetyReporting() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SafetyReportingScreen(),
      ),
    );
  }

  Future<void> _contactSupport() async {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final body = '''Hi Team,

I am facing an issue:

Description:

App Version: ${_appVersion()}
Device: ${_deviceType()}
User ID: ${userId.isEmpty ? 'N/A' : userId}
''';

    final uri = Uri(
      scheme: 'mailto',
      path: 'supportyanegi@gmail.com',
      queryParameters: {
        'subject': 'Support Request - Yanegi App',
        'body': body,
      },
    );

    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No email app found')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email app found')),
      );
    }
  }

  String _deviceType() {
    if (kIsWeb) return 'web';

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  String _appVersion() {
    const fromEnv = String.fromEnvironment('APP_VERSION', defaultValue: '');
    if (fromEnv.trim().isNotEmpty) return fromEnv;
    return '1.0.0+1';
  }

  Future<void> _openCreatorEarningsPreview() async {
    final scheme = Theme.of(context).colorScheme;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: YanegiColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome,
                  color: YanegiColors.primary, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Something exciting is coming',
                style: TextStyle(
                  color: _textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Soon, normal users will be able to make money from Yanegi.',
              style: TextStyle(
                color: _textSecondary,
                fontSize: 13.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [
                    YanegiColors.primary.withOpacity(0.20),
                    scheme.primary.withOpacity(0.10),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: YanegiColors.primary.withOpacity(0.35),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined,
                      color: YanegiColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Users can make money from this app.',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Got it',
              style: TextStyle(color: scheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openChangeContact() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _surface,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetOption('Change Email'),
            _sheetOption('View Phone Number'),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;
    if (choice == 'Change Email') {
      await _promptEmailUpdate();
      return;
    }

    _toast(
      _currentPhone.trim().isEmpty
          ? 'No verified phone number is linked to this account.'
          : 'Verified phone: $_currentPhone',
    );
  }

  Future<void> _promptEmailUpdate() async {
    final emailController = TextEditingController(text: _currentEmail.trim());
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        title: Text(
          'Update Email',
          style: TextStyle(color: _textPrimary),
        ),
        content: TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(color: _textPrimary),
          decoration: InputDecoration(
            hintText: 'name@example.com',
            hintStyle: TextStyle(color: _textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(emailController.text.trim()),
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (!mounted || result == null) return;
    final nextEmail = result.trim();
    if (nextEmail.isEmpty) {
      _toast('Email cannot be empty.');
      return;
    }

    try {
      await _userService.updateEmail(newEmail: nextEmail);
      await _userService.syncAuthContactFields();
      if (!mounted) return;
      _toast('Verification email sent. Confirm it to finalize your new email.');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'requires-recent-login') {
        _toast('Please sign in again before changing your email.');
      } else if (e.code == 'invalid-email') {
        _toast('Please enter a valid email address.');
      } else if (e.code == 'email-already-in-use') {
        _toast('That email is already used by another account.');
      } else {
        debugPrint('Email update FirebaseAuthException: ${e.code}');
        _toast('Unable to update email right now. Please try again.');
      }
    } catch (_) {
      if (!mounted) return;
      _toast('Unable to update email right now.');
    }
  }

  Future<void> _confirmDeactivate() async {
    if (_isProcessingAccountAction) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: _surface,
            title: Text(
              'Deactivate Account',
              style: TextStyle(color: _textPrimary),
            ),
            content: Text(
              'Your profile will be hidden and your account will be paused until you sign in again.',
              style: TextStyle(color: _textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'Deactivate',
                  style: TextStyle(color: Colors.red.shade400),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;
    await _deactivateAccount();
  }

  Future<void> _deactivateAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _toast('You are not signed in.');
      return;
    }

    setState(() => _isProcessingAccountAction = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'accountStatus': 'deactivated',
        'deactivatedAt': FieldValue.serverTimestamp(),
        'profileVisibility': false,
        'updatedAt': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _userService.setNearbyActivityEnabled(false);
      await _userService.setShowProfileInEventsEnabled(false);
      _invalidateServiceCaches();
      await _clearGoogleSession();
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      _toast('Account deactivated. Sign in anytime to reactivate.');
      AuthBootstrapperController.rebootstrap(navigationContext: context);
    } catch (_) {
      if (!mounted) return;
      _toast('Could not deactivate your account right now. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isProcessingAccountAction = false);
      }
    }
  }

  Future<void> _confirmDelete() async {
    if (_isProcessingAccountAction) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: _surface,
            title:
                Text('Delete Account', style: TextStyle(color: _textPrimary)),
            content: Text(
              'This is permanent. Your account will be removed and this action cannot be undone. Continue?',
              style: TextStyle(color: _textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'Delete',
                  style: TextStyle(color: Colors.red.shade400),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;
    await _deleteAccount();
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _toast('You are not signed in.');
      return;
    }

    setState(() => _isProcessingAccountAction = true);
    try {
      String usernameLower = '';
      final normalizedEmail = (user.email ?? '').trim().toLowerCase();
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        usernameLower =
            (userDoc.data()?['usernameLower'] as String?)?.trim() ?? '';
      } catch (_) {
        // Continue even if we can't read profile metadata.
      }

      await _deleteAccountData(
        uid: user.uid,
        usernameLower: usernameLower,
        normalizedEmail: normalizedEmail,
      );

      await _deleteAuthUserWithReauthFallback(user);

      await _clearGoogleSession();

      if (!mounted) return;
      _toast('Account deleted permanently.');
      AuthBootstrapperController.rebootstrap(navigationContext: context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'requires-recent-login') {
        _toast('Please log in again, then retry deleting your account.');
      } else {
        debugPrint('Account delete FirebaseAuthException: ${e.code}');
        _toast('Could not delete account right now. Please try again.');
      }
    } catch (_) {
      if (!mounted) return;
      _toast('Could not delete account right now. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isProcessingAccountAction = false);
      }
    }
  }

  Future<void> _deleteAuthUserWithReauthFallback(User user) async {
    try {
      await user.delete();
      return;
    } on FirebaseAuthException catch (e) {
      if (e.code != 'requires-recent-login') rethrow;

      final reauthed = await _tryGoogleReauth(user);
      if (!reauthed) {
        throw FirebaseAuthException(
          code: 'requires-recent-login',
          message: 'Please sign in again, then retry deleting your account.',
        );
      }

      await user.delete();
    }
  }

  Future<bool> _tryGoogleReauth(User user) async {
    final hasGoogleProvider = user.providerData
        .any((provider) => provider.providerId == 'google.com');
    if (!hasGoogleProvider) return false;

    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return false;

      final auth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );
      await user.reauthenticateWithCredential(credential);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteAccountData({
    required String uid,
    required String usernameLower,
    required String normalizedEmail,
  }) async {
    final firestore = FirebaseFirestore.instance;

    try {
      final userRef = firestore.collection('users').doc(uid);
      final batch = firestore.batch();
      batch.delete(userRef);
      batch.delete(userRef.collection('settings').doc('main'));
      if (usernameLower.isNotEmpty) {
        final usernameRef =
            firestore.collection('usernames').doc(usernameLower);
        final usernameDoc = await usernameRef.get();
        final claimedBy = (usernameDoc.data()?['userId'] as String?) ?? '';
        if (claimedBy == uid) {
          batch.delete(usernameRef);
        }
      }
      await batch.commit();
    } catch (_) {
      // Continue with auth deletion even if profile data cleanup is partial.
    }

    if (normalizedEmail.isEmpty) return;

    try {
      final duplicateDocs = await firestore
          .collection('users')
          .where('email', isEqualTo: normalizedEmail)
          .limit(20)
          .get();

      final cleanupBatch = firestore.batch();
      for (final doc in duplicateDocs.docs) {
        cleanupBatch.delete(doc.reference);
      }
      if (duplicateDocs.docs.isNotEmpty) {
        await cleanupBatch.commit();
      }
    } catch (_) {
      // Best-effort duplicate cleanup.
    }
  }

  Future<void> _clearGoogleSession() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {
      // Ignore session clear errors.
    }
  }

  /// Invalidates the Riverpod service providers whose cached state is
  /// user-specific. The providers are root-level and would otherwise persist
  /// across sign-out/sign-in, causing the next user to briefly see the
  /// previous user's ranked explore feed, message cache, or group list.
  ///
  /// Each provider has a [ref.onDispose] callback that triggers the concrete
  /// cleanup (FirebaseChatRepository.dispose, EventService.clearCaches,
  /// ExploreRecommendationService.clearCache) when invalidated here.
  void _invalidateServiceCaches() {
    ref.invalidate(chatRepositoryProvider);
    ref.invalidate(eventServiceProvider);
    ref.invalidate(exploreRecommendationServiceProvider);
  }

  Future<void> _signOut() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      LocalProfileCache.clear(uid);
    }
    ChatPeerCache.clear();
    _invalidateServiceCaches();
    // Sign out Firebase AND Google so the Google session is fully cleared.
    // Without the Google sign-out, the next "Continue with Google" tap silently
    // reuses the previous account instead of showing the account chooser.
    await _clearGoogleSession();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    _toast('Signed out');
    AuthBootstrapperController.rebootstrap(navigationContext: context);
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

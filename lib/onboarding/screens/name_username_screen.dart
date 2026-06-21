import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:yanegi/onboarding/auth_bootstrapper.dart';
import 'package:yanegi/onboarding/model/branding_lines.dart';
import 'package:yanegi/onboarding/model/onboarding_data.dart';
import 'package:yanegi/onboarding/widgets/onboarding_screen.dart';
import 'package:yanegi/widgets/app_illustration.dart';
import 'package:yanegi/services/auth_service.dart';
import 'package:yanegi/services/auth_flow_service.dart';
import 'package:yanegi/theme/yanegi_theme.dart';

/// Screen 1: Collects user's display name and unique username.
class NameUsernameScreen extends StatefulWidget {
  final OnboardingData data;
  final AuthFlowService? authFlowService;
  /// When provided, called instead of rebootstrap after a successful save.
  /// Used when this screen is pushed for back-navigation editing.
  final VoidCallback? onCompleted;

  const NameUsernameScreen({
    super.key,
    required this.data,
    this.authFlowService,
    this.onCompleted,
  });

  @override
  State<NameUsernameScreen> createState() => _NameUsernameScreenState();
}

class _NameUsernameScreenState extends State<NameUsernameScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  AuthFlowService? _defaultAuthFlowService;
  bool _isCheckingUsername = false;
  String? _errorMessage;
  List<String> _suggestions = [];
  bool _isLoadingSuggestions = false;

  AuthFlowService get _authFlowService =>
      widget.authFlowService ?? (_defaultAuthFlowService ??= AuthFlowService());

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.data.name ?? '');
    _usernameController =
        TextEditingController(text: widget.data.username ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _nameController.text.trim().isNotEmpty &&
      _usernameController.text.trim().isNotEmpty;

  String? _resolveCurrentUserId() {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Generates a cleaned base from the typed username (lowercase,
  /// alphanumeric + underscore only, max 18 chars so suffixes fit).
  String _cleanBase(String raw) {
    final cleaned = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '')
        .replaceAll(RegExp(r'_+'), '_');
    return cleaned.length > 18 ? cleaned.substring(0, 18) : cleaned;
  }

  /// Checks a small set of suffix candidates and returns up to 3 available ones.
  Future<void> _loadSuggestions(String takenUsername) async {
    final base = _cleanBase(takenUsername);
    if (base.isEmpty) return;

    setState(() => _isLoadingSuggestions = true);

    final currentUserId = _resolveCurrentUserId();
    final candidates = [
      '${base}1',
      '${base}2',
      '${base}3',
      '${base}_x',
      '${base}99',
      '${base}_23',
      '${base}007',
      '${base}_real',
    ];

    final found = <String>[];
    for (final candidate in candidates) {
      if (found.length >= 3) break;
      try {
        final available = await _authFlowService.isUsernameAvailable(
          candidate,
          exceptUserId: currentUserId,
        );
        if (available) found.add(candidate);
      } catch (_) {
        // Skip unavailable-to-check candidates silently.
      }
    }

    if (mounted) setState(() {
      _suggestions = found;
      _isLoadingSuggestions = false;
    });
  }

  void _applySuggestion(String suggestion) {
    _usernameController.text = suggestion;
    setState(() {
      _errorMessage = null;
      _suggestions = [];
    });
  }

  Future<void> _onNext() async {
    if (_isCheckingUsername) return;
    setState(() {
      _errorMessage = null;
      _suggestions = [];
    });

    widget.data.name = _nameController.text.trim();
    widget.data.username = _usernameController.text.trim();

    setState(() => _isCheckingUsername = true);

    final currentUserId = _resolveCurrentUserId();
    bool usernameAvailable;
    try {
      usernameAvailable = await _authFlowService.isUsernameAvailable(
        widget.data.username!,
        exceptUserId: currentUserId,
      );
    } catch (e) {
      print('TESTING [ERROR]: isUsernameAvailable failed: $e');
      if (!mounted) return;
      setState(() {
        _isCheckingUsername = false;
        _errorMessage = 'Could not verify username. Please try again.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not verify username. Please try again.'),
        ),
      );
      return;
    }

    if (!usernameAvailable) {
      if (!mounted) return;
      setState(() {
        _isCheckingUsername = false;
        _errorMessage = 'Username not available, try another';
      });
      // Load alternatives in the background; UI updates when ready.
      _loadSuggestions(widget.data.username!);
      return;
    }

    print('TESTING [ONBOARDING STEP 1]: Reserving username');
    var didSave = false;
    try {
      await _authFlowService.completeProfile(
        name: widget.data.name!,
        username: widget.data.username!,
      );
      didSave = true;
    } catch (e) {
      print('TESTING [ERROR]: Failed saving step 1 data: $e');
      if (!mounted) return;
      setState(() => _errorMessage = 'Could not save this step. Please retry.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save this step. Please retry.'),
        ),
      );
      return;
    } finally {
      if (mounted) {
        setState(() => _isCheckingUsername = false);
      }
    }

    if (didSave && mounted) {
      if (widget.onCompleted != null) {
        widget.onCompleted!();
      } else {
        AuthBootstrapperController.rebootstrap(
          navigationContext: context,
          resetNavigation: false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScreen(
      icon: Icons.person_rounded,
      illustration: const AppIllustration(AppIllustrations.onboardHello),
      title: 'What\'s your name?',
      subtitle: 'Pick a name and a unique @username.',
      brandingLines: yanegiBrandingLines.sublist(4, 8),
      currentStep: 1,
      totalSteps: 5,
      buttonLabel: 'Continue',
      onButtonPressed: _isValid && !_isCheckingUsername ? _onNext : null,
      onClose: () async {
        await AuthService().signOut();
        if (!context.mounted) return;
        AuthBootstrapperController.rebootstrap(navigationContext: context);
      },
      inputSection: _buildInputs(context),
    );
  }

  Widget _buildInputs(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTextField(
          controller: _nameController,
          label: 'Display Name',
          hint: 'Your name',
          icon: Icons.badge_rounded,
        ),
        const SizedBox(height: YanegiSpacing.md),
        _buildTextField(
          controller: _usernameController,
          label: 'Username',
          hint: 'Choose a username',
          icon: Icons.alternate_email_rounded,
          prefix: '@',
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: YanegiSpacing.sm),
          Text(
            _errorMessage!,
            style: const TextStyle(
              color: Colors.redAccent,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        if (_isLoadingSuggestions) ...[
          const SizedBox(height: YanegiSpacing.sm),
          Row(
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: YanegiColors.onbAccent.withAlpha(180),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Finding available usernames…',
                style: TextStyle(
                  color: YanegiColors.onbInkFaint,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: YanegiSpacing.sm),
          Text(
            'Try one of these:',
            style: TextStyle(
              color: YanegiColors.onbInkSoft,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: YanegiSpacing.xs),
          Wrap(
            spacing: YanegiSpacing.xs,
            runSpacing: YanegiSpacing.xs,
            children: _suggestions.map((s) => _buildSuggestionChip(s)).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildSuggestionChip(String suggestion) {
    return GestureDetector(
      onTap: () => _applySuggestion(suggestion),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: YanegiSpacing.md,
          vertical: YanegiSpacing.xs + 2,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(YanegiRadius.pill),
          color: YanegiColors.onbAccent.withAlpha(20),
          border: Border.all(
            color: YanegiColors.onbAccent.withAlpha(100),
            width: 1,
          ),
        ),
        child: Text(
          '@$suggestion',
          style: const TextStyle(
            color: YanegiColors.onbAccent,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? prefix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: YanegiColors.onbInkSoft,
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: YanegiSpacing.sm),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(YanegiRadius.md),
            color: YanegiColors.onbField.withAlpha(180),
            border: Border.all(
              color: YanegiColors.onbBorder.withAlpha(120),
              width: 1,
            ),
          ),
          child: TextField(
            controller: controller,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
              color: YanegiColors.onbInk,
              fontSize: 16,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: YanegiColors.onbInkFaint,
                fontSize: 15,
              ),
              prefixIcon: Icon(icon, color: YanegiColors.onbAccent, size: 22),
              prefixText: prefix,
              prefixStyle: const TextStyle(
                color: YanegiColors.onbAccent,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: YanegiSpacing.md,
                vertical: YanegiSpacing.md,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

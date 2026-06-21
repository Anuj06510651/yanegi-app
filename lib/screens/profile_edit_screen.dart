import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/user_service.dart';
import '../theme/yanegi_theme.dart';
import '../utils/error_handler.dart';

class ProfileEditScreen extends StatefulWidget {
  final String initialName;
  final String initialUsername;
  final String initialBio;

  const ProfileEditScreen({
    super.key,
    required this.initialName,
    required this.initialUsername,
    required this.initialBio,
  });

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final UserService _userService = UserService();

  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  Timer? _usernameDebounce;

  bool _isSaving = false;
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _usernameFeedback;
  String _initialUsernameLower = '';
  UsernameQuotaStatus _quotaStatus =
      const UsernameQuotaStatus(usedThisMonth: 0, remaining: 2);

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _usernameController = TextEditingController(text: widget.initialUsername);
    _bioController = TextEditingController(text: widget.initialBio);
    _initialUsernameLower = _normalizeUsername(_usernameController.text);
    _usernameController.addListener(_onUsernameInputChanged);
    _primeUsernameState();
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _usernameController.removeListener(_onUsernameInputChanged);
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  String _normalizeUsername(String raw) {
    var value = raw.trim().toLowerCase();
    if (value.startsWith('@')) {
      value = value.substring(1);
    }
    return value;
  }

  bool get _usernameChanged {
    final normalized = _normalizeUsername(_usernameController.text);
    return normalized.isNotEmpty && normalized != _initialUsernameLower;
  }

  bool get _quotaExceededForAttempt =>
      _usernameChanged && _quotaStatus.exhausted;

  bool get _saveDisabled {
    if (_isSaving || _isCheckingUsername) return true;
    if (_quotaExceededForAttempt) return true;
    if (_usernameChanged && _isUsernameAvailable == false) return true;
    return false;
  }

  Future<void> _primeUsernameState() async {
    if (_uid.isEmpty) return;
    try {
      final quota = await _userService.getUsernameQuotaStatus(uid: _uid);
      if (!mounted) return;
      setState(() {
        _quotaStatus = quota;
        _isUsernameAvailable = true;
        _usernameFeedback =
            'Usernames can be changed ${quota.remaining}/2 times this month.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isUsernameAvailable = true;
        _usernameFeedback = null;
      });
    }
  }

  void _onUsernameInputChanged() {
    _usernameDebounce?.cancel();

    final normalized = _normalizeUsername(_usernameController.text);
    if (normalized.isEmpty) {
      setState(() {
        _isUsernameAvailable = false;
        _isCheckingUsername = false;
        _usernameFeedback = 'Username is required.';
      });
      return;
    }

    if (!_usernameChanged) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = true;
        _usernameFeedback =
            'Current username. ${_quotaStatus.remaining}/2 edits remaining this month.';
      });
      return;
    }

    if (_quotaStatus.exhausted) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameFeedback =
            'You have reached the 2 username changes limit for this month.';
      });
      return;
    }

    setState(() {
      _isCheckingUsername = true;
      _usernameFeedback = 'Checking username availability...';
    });

    _usernameDebounce = Timer(const Duration(milliseconds: 450), () async {
      final available = await _userService.checkUsernameAvailable(normalized);
      if (!mounted) return;
      if (_normalizeUsername(_usernameController.text) != normalized) return;
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = available;
        _usernameFeedback = available
            ? 'Username is available.'
            : 'That username is already taken.';
      });
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final uname = _normalizeUsername(_usernameController.text);
    final bio = _bioController.text.trim();

    if (_uid.isEmpty) return;
    if (name.isEmpty || uname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and username are required.')),
      );
      return;
    }

    if (_quotaExceededForAttempt) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'You have reached the 2 username changes limit for this month.'),
        ),
      );
      return;
    }

    if (_usernameChanged) {
      final available = await _userService.checkUsernameAvailable(uname);
      if (!available) {
        if (!mounted) return;
        setState(() {
          _isUsernameAvailable = false;
          _usernameFeedback = 'That username is already taken.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Username is already taken.')),
        );
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      await _userService.updateProfileFields(
        name: name,
        username: uname,
        bio: bio,
      );
      await _userService.syncAuthContactFields();

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, stack) {
      if (!mounted) return;
      final raw = e.toString();
      if (raw.contains('Username taken')) {
        ErrorHandler.showUserMessage(
          context,
          AppErrorType.profileUsernameTaken,
          error: e,
          stackTrace: stack,
          where: 'profile_edit._save',
        );
      } else if (raw.contains('Limit reached')) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('You can only change username 2 times per month.'),
          ),
        );
      } else {
        ErrorHandler.showUserMessage(
          context,
          AppErrorType.profileSaveFailed,
          error: e,
          stackTrace: stack,
          where: 'profile_edit._save',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: YanegiColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'Edit Profile',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          actions: [
            TextButton(
              onPressed: _saveDisabled ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        color: YanegiColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _field(
              label: 'Display Name',
              hint: 'Enter your name',
              controller: _nameController,
            ),
            const SizedBox(height: 12),
            _field(
              label: 'Username',
              hint: '@username',
              controller: _usernameController,
              feedbackText: _usernameFeedback,
              feedbackColor: _isCheckingUsername
                  ? YanegiColors.textSecondary
                  : (_isUsernameAvailable == true
                      ? const Color(0xFF4ADE80)
                      : const Color(0xFFF87171)),
            ),
            if (_quotaExceededForAttempt)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Username edit quota reached (2/month). Try again next month.',
                  style: TextStyle(
                    color: const Color(0xFFF87171).withAlpha(230),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            _field(
              label: 'Bio',
              hint: 'Tell people about yourself',
              controller: _bioController,
              maxLines: 4,
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required String hint,
    required TextEditingController controller,
    int maxLines = 1,
    String? feedbackText,
    Color? feedbackColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: YanegiColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: YanegiColors.textSecondary),
            filled: true,
            fillColor: YanegiColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: YanegiColors.textSecondary.withAlpha(40)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: YanegiColors.textSecondary.withAlpha(40)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: YanegiColors.primary),
            ),
          ),
        ),
        if (feedbackText != null && feedbackText.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              feedbackText,
              style: TextStyle(
                color: feedbackColor ?? YanegiColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:yanegi/onboarding/auth_bootstrapper.dart';
import 'package:yanegi/onboarding/model/branding_lines.dart';
import 'package:yanegi/onboarding/model/onboarding_data.dart';
import 'package:yanegi/onboarding/widgets/onboarding_screen.dart';
import 'package:yanegi/widgets/app_illustration.dart';
import 'package:yanegi/theme/yanegi_theme.dart';
import 'package:yanegi/services/auth_service.dart';
import 'package:yanegi/services/user_service.dart';
import 'package:yanegi/onboarding/screens/demographics_screen.dart';

/// Screen 5: Vibe tag selection. User must pick at least 3 tags.
class VibeTagsScreen extends StatefulWidget {
  final OnboardingData data;
  /// When provided, called instead of rebootstrap after a successful save.
  final VoidCallback? onCompleted;

  const VibeTagsScreen({super.key, required this.data, this.onCompleted});

  @override
  State<VibeTagsScreen> createState() => _VibeTagsScreenState();
}

class _VibeTagsScreenState extends State<VibeTagsScreen> {
  final UserService _userService = UserService();
  late final Set<String> _selectedVibes;
  bool _isSaving = false;

  static const List<String> _allVibes = [
    'Music',
    'Art',
    'Fitness',
    'Photography',
    'Foodie',
    'Travel',
    'Tech',
    'Books',
    'Gaming',
    'Wellness',
    'Movies',
    'Nature',
    'Karaoke',
    'Coffee',
    'Sports',
    'Dance',
    'Pets',
    'Theatre',
    'Science',
    'Writing',
  ];

  @override
  void initState() {
    super.initState();
    _selectedVibes = Set<String>.from(widget.data.vibes);
  }

  bool get _isValid => _selectedVibes.length >= 3;

  void _toggleVibe(String vibe) {
    setState(() {
      if (_selectedVibes.contains(vibe)) {
        _selectedVibes.remove(vibe);
      } else {
        _selectedVibes.add(vibe);
      }
    });
  }

  Future<void> _onNext() async {
    if (_isSaving) return;
    widget.data.vibes = _selectedVibes.toList();
    setState(() => _isSaving = true);

    print('TESTING [ONBOARDING STEP 4]: Saving vibes to Firestore');
    var didSave = false;
    try {
      await _userService.saveUser(
        name: widget.data.name ?? '',
        username: widget.data.username ?? '',
        gender: widget.data.gender,
        dob: widget.data.dob,
        avatarUrl: widget.data.avatarPath,
        vibes: widget.data.vibes,
        onboardingStep: OnboardingData.stepBio,
        hasCompletedProfile: false,
      );
      didSave = true;
    } catch (e) {
      print('TESTING [ERROR]: Failed saving step 4 data (vibes): $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save this step. Please retry.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
      icon: Icons.auto_awesome_rounded,
      illustration: const AppIllustration(AppIllustrations.onboardVibe),
      title: 'Pick your vibes',
      subtitle: 'Choose at least 3 you love.',
      brandingLines: yanegiBrandingLines.sublist(16, 20),
      currentStep: 3,
      totalSteps: 5,
      buttonLabel: 'Continue (${_selectedVibes.length}/3+)',
      onButtonPressed: _isValid && !_isSaving ? _onNext : null,
      onBack: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DemographicsScreen(
            data: widget.data,
            onCompleted: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      onClose: () async {
        await AuthService().signOut();
        if (!context.mounted) return;
        AuthBootstrapperController.rebootstrap(navigationContext: context);
      },
      inputSection: _buildVibeGrid(),
    );
  }

  Widget _buildVibeGrid() {
    return Wrap(
      spacing: YanegiSpacing.sm,
      runSpacing: YanegiSpacing.sm,
      alignment: WrapAlignment.center,
      children: _allVibes.map((vibe) {
        final isSelected = _selectedVibes.contains(vibe);
        return GestureDetector(
          onTap: () => _toggleVibe(vibe),
          child: AnimatedContainer(
            duration: YanegiDurations.fast,
            curve: YanegiCurves.smooth,
            padding: const EdgeInsets.symmetric(
              horizontal: YanegiSpacing.md,
              vertical: YanegiSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(YanegiRadius.pill),
              color: isSelected
                  ? YanegiColors.onbAccent.withAlpha(38)
                  : YanegiColors.onbField.withAlpha(180),
              border: Border.all(
                color: isSelected
                    ? YanegiColors.onbAccent
                    : YanegiColors.onbBorder.withAlpha(120),
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: YanegiColors.onbAccent.withAlpha(40),
                        blurRadius: 8,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
            child: Text(
              vibe,
              style: TextStyle(
                color: isSelected
                    ? YanegiColors.onbAccent
                    : YanegiColors.onbInkSoft,
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

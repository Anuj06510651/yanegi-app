import 'package:flutter/material.dart';
import 'package:yanegi/onboarding/auth_bootstrapper.dart';
import 'package:yanegi/onboarding/model/branding_lines.dart';
import 'package:yanegi/onboarding/model/onboarding_data.dart';
import 'package:yanegi/onboarding/widgets/onboarding_screen.dart';
import 'package:yanegi/widgets/app_illustration.dart';
import 'package:yanegi/theme/yanegi_theme.dart';
import 'package:yanegi/services/auth_service.dart';
import 'package:yanegi/services/user_service.dart';
import 'package:yanegi/onboarding/screens/name_username_screen.dart';

/// Screen 3: Collects gender and date of birth.
class DemographicsScreen extends StatefulWidget {
  final OnboardingData data;
  /// When provided, called instead of rebootstrap after a successful save.
  final VoidCallback? onCompleted;

  const DemographicsScreen({super.key, required this.data, this.onCompleted});

  @override
  State<DemographicsScreen> createState() => _DemographicsScreenState();
}

class _DemographicsScreenState extends State<DemographicsScreen> {
  final UserService _userService = UserService();
  String? _selectedGender;
  DateTime? _selectedDob;
  bool _isSaving = false;

  final List<_GenderOption> _genderOptions = const [
    _GenderOption('Male', Icons.male_rounded),
    _GenderOption('Female', Icons.female_rounded),
    _GenderOption('Non-binary', Icons.transgender_rounded),
    _GenderOption('Prefer not to say', Icons.do_not_disturb_alt_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _selectedGender = widget.data.gender;
    _selectedDob = widget.data.dob;
  }

  bool get _isValid => _selectedGender != null && _selectedDob != null;

  Future<void> _onNext() async {
    if (_isSaving) return;
    widget.data.gender = _selectedGender;
    widget.data.dob = _selectedDob;
    setState(() => _isSaving = true);

    print('TESTING [ONBOARDING STEP 2]: Updating gender & DOB in Firestore');
    var didSave = false;
    try {
      await _userService.saveUser(
        name: widget.data.name ?? '',
        username: widget.data.username ?? '',
        gender: widget.data.gender,
        dob: widget.data.dob,
        onboardingStep: OnboardingData.stepVibe,
        hasCompletedProfile: false,
      );
      didSave = true;
    } catch (e) {
      print('TESTING [ERROR]: Failed saving step 2 data: $e');
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

  void _pickDate() {
    final now = DateTime.now();
    final initial = _selectedDob ?? DateTime(2000, 1, 1);
    int selDay = initial.day;
    int selMonth = initial.month;
    int selYear = initial.year;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setModal) {
          final daysInMonth =
              DateTime(selYear, selMonth + 1, 0).day;
          if (selDay > daysInMonth) selDay = daysInMonth;

          Widget wheel({
            required int itemCount,
            required int selected,
            required String Function(int) label,
            required ValueChanged<int> onChanged,
          }) {
            final ctrl = FixedExtentScrollController(
                initialItem: selected - 1);
            return Expanded(
              child: ListWheelScrollView.useDelegate(
                controller: ctrl,
                itemExtent: 42,
                perspective: 0.003,
                diameterRatio: 1.6,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: (i) => onChanged(i + 1),
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: itemCount,
                  builder: (_, i) {
                    final isSelected = i + 1 == selected;
                    return Center(
                      child: Text(
                        label(i + 1),
                        style: TextStyle(
                          color: isSelected
                              ? YanegiColors.onbInk
                              : YanegiColors.onbInkFaint,
                          fontSize: isSelected ? 18 : 15,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          }

          const months = [
            'Jan','Feb','Mar','Apr','May','Jun',
            'Jul','Aug','Sep','Oct','Nov','Dec'
          ];

          return Container(
            decoration: const BoxDecoration(
              color: YanegiColors.onbField,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: YanegiColors.onbBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Date of Birth',
                  style: TextStyle(
                    color: YanegiColors.onbInk,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 180,
                  child: Stack(
                    children: [
                      // Selection highlight bar
                      Center(
                        child: Container(
                          height: 42,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: YanegiColors.onbAccent.withAlpha(30),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: YanegiColors.onbAccent.withAlpha(80),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          wheel(
                            itemCount: daysInMonth,
                            selected: selDay,
                            label: (i) => i.toString().padLeft(2, '0'),
                            onChanged: (v) =>
                                setModal(() => selDay = v),
                          ),
                          wheel(
                            itemCount: 12,
                            selected: selMonth,
                            label: (i) => months[i - 1],
                            onChanged: (v) =>
                                setModal(() => selMonth = v),
                          ),
                          wheel(
                            itemCount: now.year - 1920 + 1,
                            selected: selYear - 1919,
                            label: (i) => (1919 + i).toString(),
                            onChanged: (v) =>
                                setModal(() => selYear = 1919 + v),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: YanegiColors.onbAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedDob =
                            DateTime(selYear, selMonth, selDay);
                      });
                      Navigator.of(ctx).pop();
                    },
                    child: const Text(
                      'Confirm',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScreen(
      icon: Icons.calendar_today_rounded,
      illustration: const AppIllustration(AppIllustrations.onboardDemographics),
      title: 'About you',
      subtitle: 'A few quick basics.',
      brandingLines: yanegiBrandingLines.sublist(8, 12),
      currentStep: 2,
      totalSteps: 5,
      buttonLabel: 'Continue',
      onButtonPressed: _isValid && !_isSaving ? _onNext : null,
      onBack: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NameUsernameScreen(
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
      inputSection: _buildInputs(context),
    );
  }

  Widget _buildInputs(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gender',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: YanegiColors.onbInkSoft,
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: YanegiSpacing.sm),
        Wrap(
          spacing: YanegiSpacing.sm,
          runSpacing: YanegiSpacing.sm,
          children: _genderOptions.map((option) {
            final isSelected = _selectedGender == option.label;
            return GestureDetector(
              onTap: () => setState(() => _selectedGender = option.label),
              child: AnimatedContainer(
                duration: YanegiDurations.fast,
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
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      option.icon,
                      size: 18,
                      color: isSelected
                          ? YanegiColors.onbAccent
                          : YanegiColors.onbInkFaint,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      option.label,
                      style: TextStyle(
                        color: isSelected
                            ? YanegiColors.onbAccent
                            : YanegiColors.onbInkSoft,
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: YanegiSpacing.lg),
        Text(
          'Date of Birth',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: YanegiColors.onbInkSoft,
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: YanegiSpacing.sm),
        GestureDetector(
          onTap: _pickDate,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: YanegiSpacing.md,
              vertical: YanegiSpacing.md,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(YanegiRadius.md),
              color: YanegiColors.onbField.withAlpha(180),
              border: Border.all(
                color: _selectedDob != null
                    ? YanegiColors.onbAccent.withAlpha(100)
                    : YanegiColors.onbBorder.withAlpha(120),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.cake_rounded,
                  color: _selectedDob != null
                      ? YanegiColors.onbAccent
                      : YanegiColors.onbInkFaint,
                  size: 22,
                ),
                const SizedBox(width: YanegiSpacing.md),
                Text(
                  _selectedDob != null
                      ? '${_selectedDob!.day} ${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][_selectedDob!.month - 1]} ${_selectedDob!.year}'
                      : 'Select your date of birth',
                  style: TextStyle(
                    color: _selectedDob != null
                        ? YanegiColors.onbInk
                        : YanegiColors.onbInkFaint,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.chevron_right_rounded,
                  color: YanegiColors.onbInkFaint,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: YanegiSpacing.sm),
        Row(
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 12,
              color: YanegiColors.onbInkFaint,
            ),
            const SizedBox(width: 4),
            Text(
              'Used only for age-gating. Never shared.',
              style: const TextStyle(
                color: YanegiColors.onbInkFaint,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GenderOption {
  final String label;
  final IconData icon;
  const _GenderOption(this.label, this.icon);
}

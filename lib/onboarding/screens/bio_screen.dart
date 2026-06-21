import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yanegi/onboarding/auth_bootstrapper.dart';
import 'package:yanegi/onboarding/screens/vibe_tags_screen.dart';
import 'package:yanegi/onboarding/model/branding_lines.dart';
import 'package:yanegi/onboarding/model/onboarding_data.dart';
import 'package:yanegi/onboarding/widgets/onboarding_screen.dart';
import 'package:yanegi/widgets/app_illustration.dart';
import 'package:yanegi/theme/yanegi_theme.dart';
import 'package:yanegi/services/auth_service.dart';
import 'package:yanegi/services/user_service.dart';

/// Screen 4 of 5: Bio input + terms acceptance.
class BioScreen extends StatefulWidget {
  final OnboardingData data;
  /// When provided, called instead of rebootstrap after a successful save.
  final VoidCallback? onCompleted;

  const BioScreen({super.key, required this.data, this.onCompleted});

  @override
  State<BioScreen> createState() => _BioScreenState();
}

class _BioScreenState extends State<BioScreen> {
  final UserService _userService = UserService();
  late final TextEditingController _bioController;
  bool _hasAcceptedTerms = false;
  bool _isSaving = false;

  static const int _maxLength = 150;
  static final Uri _termsUri = Uri.parse('https://policy-henna.vercel.app/');

  @override
  void initState() {
    super.initState();
    _bioController = TextEditingController(text: widget.data.bio ?? '');
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  bool get _isValid => _bioController.text.trim().isNotEmpty;
  bool get _canFinish => _isValid && _hasAcceptedTerms;

  void _showTermsDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: YanegiColors.onbField,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(YanegiRadius.xl),
        ),
        child: Padding(
          padding: const EdgeInsets.all(YanegiSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    color: YanegiColors.onbAccent,
                    size: 22,
                  ),
                  const SizedBox(width: YanegiSpacing.sm),
                  Text(
                    'Terms & Conditions',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          color: YanegiColors.onbInk,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: YanegiSpacing.md),
              const Divider(color: YanegiColors.onbBorder, height: 1),
              const SizedBox(height: YanegiSpacing.md),
              ..._termsBullets.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: YanegiSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '•  ',
                        style: TextStyle(
                          color: YanegiColors.onbAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item,
                          style: const TextStyle(
                            color: YanegiColors.onbInkSoft,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: YanegiSpacing.md),
              // Full terms link — explicit tap so user opts in to leaving the app.
              GestureDetector(
                onTap: () async {
                  await launchUrl(_termsUri, mode: LaunchMode.platformDefault);
                },
                child: Text(
                  'Read full Terms & Conditions →',
                  style: TextStyle(
                    color: YanegiColors.onbAccent.withAlpha(200),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: YanegiColors.onbAccent.withAlpha(200),
                  ),
                ),
              ),
              const SizedBox(height: YanegiSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: YanegiColors.onbAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(YanegiRadius.md),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: YanegiSpacing.md,
                    ),
                  ),
                  child: const Text(
                    'Got it',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const List<String> _termsBullets = [
    'Treat every person on Yanegi with respect — no harassment, hate speech, or bullying.',
    'Keep your profile honest. Impersonating others or posting misleading content is not allowed.',
    'Only share content you own or have permission to use.',
    'Report anything that feels unsafe. We act quickly on all reports.',
    'Your data is used only to personalise your Yanegi experience and is never sold to third parties.',
  ];

  Future<void> _onFinish() async {
    if (_isSaving) return;
    widget.data.bio = _bioController.text.trim();
    setState(() => _isSaving = true);

    print('TESTING [ONBOARDING STEP 5]: Finishing & saving bio to Firestore');
    var didSave = false;
    try {
      await _userService.saveUser(
        name: widget.data.name ?? '',
        username: widget.data.username ?? '',
        gender: widget.data.gender,
        dob: widget.data.dob,
        avatarUrl: widget.data.avatarPath,
        bio: widget.data.bio,
        vibes: widget.data.vibes,
        onboardingStep: OnboardingData.stepPhoto,
        hasCompletedProfile: false,
      );
      didSave = true;
    } catch (e) {
      debugPrint('TESTING [ERROR]: Error saving user at final step: $e');
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
      icon: Icons.edit_note_rounded,
      illustration: const AppIllustration(AppIllustrations.onboardBio),
      title: 'Tell your story',
      subtitle: 'A line or two about you.',
      brandingLines: yanegiBrandingLines.sublist(6, 9),
      currentStep: 4,
      totalSteps: 5,
      buttonLabel: 'Finish & explore',
      onButtonPressed: _canFinish && !_isSaving ? _onFinish : null,
      onBack: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VibeTagsScreen(
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
      inputSection: _buildBioInput(context),
    );
  }

  Widget _buildBioInput(BuildContext context) {
    final charCount = _bioController.text.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
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
            controller: _bioController,
            onChanged: (_) => setState(() {}),
            maxLines: 5,
            maxLength: _maxLength,
            style: const TextStyle(
              color: YanegiColors.onbInk,
              fontSize: 16,
              height: 1.5,
            ),
            decoration: InputDecoration(
              hintText: 'Share a little about yourself.',
              hintStyle: TextStyle(
                color: YanegiColors.onbInkFaint.withAlpha(150),
                fontSize: 14,
                height: 1.5,
              ),
              border: InputBorder.none,
              counterText: '',
              contentPadding: const EdgeInsets.all(YanegiSpacing.md),
            ),
          ),
        ),
        const SizedBox(height: YanegiSpacing.sm),
        Text(
          '$charCount / $_maxLength',
          style: TextStyle(
            color: charCount > _maxLength * 0.9
                ? YanegiColors.onbAccent
                : YanegiColors.onbInkFaint,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: YanegiSpacing.md),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: YanegiSpacing.sm,
            vertical: YanegiSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: YanegiColors.onbField.withAlpha(130),
            borderRadius: BorderRadius.circular(YanegiRadius.md),
            border: Border.all(
              color: YanegiColors.onbBorder.withAlpha(110),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _hasAcceptedTerms,
                onChanged: (value) {
                  setState(() => _hasAcceptedTerms = value ?? false);
                },
                activeColor: YanegiColors.onbAccent,
                checkColor: Colors.white,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      const Text(
                        'I agree to the',
                        style: TextStyle(
                          color: YanegiColors.onbInkSoft,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      InkWell(
                        onTap: _showTermsDialog,
                        child: const Text(
                          'Terms & Conditions',
                          style: TextStyle(
                            color: YanegiColors.onbAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                            decorationColor: YanegiColors.onbAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

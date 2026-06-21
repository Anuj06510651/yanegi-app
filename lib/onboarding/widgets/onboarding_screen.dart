import 'package:flutter/material.dart';
import 'package:yanegi/theme/yanegi_theme.dart';

/// Reusable skeleton widget for all onboarding screens.
/// Provides a consistent layout: illustration area, title/subtitle,
/// dynamic input section, CTA button, and optional footer.
class OnboardingScreen extends StatelessWidget {
  final IconData icon;
  final Widget? illustration;
  final String title;
  final String subtitle;
  final List<String>? brandingLines;
  final Widget inputSection;
  final String buttonLabel;
  final VoidCallback? onButtonPressed;
  final VoidCallback? onBack;
  final VoidCallback? onClose;
  final Widget? footer;
  final int currentStep;
  final int totalSteps;

  const OnboardingScreen({
    super.key,
    required this.icon,
    this.illustration,
    required this.title,
    required this.subtitle,
    this.brandingLines,
    required this.inputSection,
    this.buttonLabel = 'Continue',
    this.onButtonPressed,
    this.onBack,
    this.onClose,
    this.footer,
    this.currentStep = 0,
    this.totalSteps = 6,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              YanegiColors.onbBgSoft,
              YanegiColors.onbBg,
              YanegiColors.onbBgSoft,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Progress indicator with optional back / close buttons
              if (currentStep > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: YanegiSpacing.lg,
                    vertical: YanegiSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      if (onBack != null) ...[
                        GestureDetector(
                          onTap: onBack,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: YanegiColors.onbField,
                              border: Border.all(
                                color: YanegiColors.onbBorder,
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              color: YanegiColors.onbInkSoft,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: YanegiSpacing.sm),
                      ],
                      Expanded(child: _buildProgressBar()),
                      if (onClose != null) ...[
                        const SizedBox(width: YanegiSpacing.sm),
                        GestureDetector(
                          onTap: onClose,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: YanegiColors.onbField,
                              border: Border.all(
                                color: YanegiColors.onbBorder,
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: YanegiColors.onbInkSoft,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: YanegiSpacing.lg,
                  ),
                  child: Column(
                    children: [
                      SizedBox(height: size.height * 0.03),

                      // Icon / Illustration area
                      _buildIllustration(size),

                      const SizedBox(height: YanegiSpacing.lg),

                      // Title
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'PlayfairDisplay',
                          color: YanegiColors.onbInk,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          height: 1.12,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 10),

                      // Subtitle
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: YanegiColors.onbInkSoft,
                          fontSize: 15.5,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                          fontVariations: [FontVariation('wght', 650)],
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: YanegiSpacing.xl),

                      // Dynamic input section
                      inputSection,

                      const SizedBox(height: YanegiSpacing.xl),
                    ],
                  ),
                ),
              ),

              // CTA Button
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: YanegiSpacing.lg,
                ),
                child: _buildCTAButton(theme),
              ),

              // Footer
              if (footer != null)
                Padding(
                  padding: const EdgeInsets.only(top: YanegiSpacing.md),
                  child: footer!,
                ),

              const SizedBox(height: YanegiSpacing.md),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Row(
      children: List.generate(totalSteps, (index) {
        final isActive = index < currentStep;
        final isCurrent = index == currentStep;
        return Expanded(
          child: AnimatedContainer(
            duration: YanegiDurations.standard,
            curve: YanegiCurves.smooth,
            height: 3,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(YanegiRadius.pill),
              color: isActive
                  ? YanegiColors.onbAccent
                  : isCurrent
                      ? YanegiColors.onbAccent.withAlpha(128)
                      : YanegiColors.onbBorder,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildIllustration(Size size) {
    if (illustration != null) {
      return SizedBox(
        width: size.width * 0.58,
        height: size.width * 0.52,
        child: Center(child: illustration!),
      );
    }

    // Map common onboarding icons to friendly emoji
    final emoji = _iconToEmoji(icon);

    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer glow ring
        Container(
          width: size.width * 0.46,
          height: size.width * 0.46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                YanegiColors.onbAccent.withAlpha(24),
                Colors.transparent,
              ],
            ),
          ),
        ),
        // Inner surface ring
        Container(
          width: size.width * 0.32,
          height: size.width * 0.32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1A2235),
            border: Border.all(
              color: YanegiColors.onbAccent.withAlpha(50),
              width: 1.5,
            ),
          ),
        ),
        // Emoji
        Text(
          emoji,
          style: TextStyle(
            fontSize: size.width * 0.13,
            height: 1,
          ),
        ),
      ],
    );
  }

  static String _iconToEmoji(IconData icon) {
    if (icon == Icons.person_rounded || icon == Icons.account_circle_rounded) {
      return '👤';
    }
    if (icon == Icons.calendar_today_rounded ||
        icon == Icons.cake_rounded) {
      return '🎂';
    }
    if (icon == Icons.tag_rounded || icon == Icons.style_rounded ||
        icon == Icons.local_offer_rounded) {
      return '🏷️';
    }
    if (icon == Icons.photo_camera_rounded ||
        icon == Icons.add_a_photo_rounded) {
      return '📸';
    }
    if (icon == Icons.star_rounded || icon == Icons.workspace_premium_rounded) {
      return '⭐';
    }
    if (icon == Icons.location_on_rounded || icon == Icons.map_rounded) {
      return '📍';
    }
    if (icon == Icons.waving_hand_rounded || icon == Icons.celebration_rounded) {
      return '👋';
    }
    return '✨';
  }

  Widget _buildCTAButton(ThemeData theme) {
    final isEnabled = onButtonPressed != null;

    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: onButtonPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isEnabled ? YanegiColors.onbAccent : YanegiColors.onbBorder,
          disabledBackgroundColor: YanegiColors.onbBorder,
          foregroundColor: isEnabled ? Colors.white : YanegiColors.onbInkFaint,
          disabledForegroundColor: YanegiColors.onbInkFaint,
          elevation: isEnabled ? 2 : 0,
          shadowColor: isEnabled
              ? YanegiColors.onbAccent.withAlpha(110)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          buttonLabel,
          style: theme.textTheme.titleLarge?.copyWith(
            color: isEnabled ? Colors.white : YanegiColors.textTertiary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

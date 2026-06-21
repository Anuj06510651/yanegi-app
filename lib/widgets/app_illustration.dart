import 'package:flutter/material.dart';

/// Asset names for the bundled line-art illustrations.
///
/// These are soft-white, transparent-background PNGs designed to sit on
/// Yanegi's dark surfaces (onboarding gradient, tutorial cards, sheets).
class AppIllustrations {
  AppIllustrations._();

  static const String _base = 'assets/illustrations';

  // Onboarding flow
  static const String onboardHello = '$_base/onboard_hello.png';
  static const String onboardDemographics = '$_base/onboard_demographics.png';
  static const String onboardVibe = '$_base/onboard_vibe.png';
  static const String onboardBio = '$_base/onboard_bio.png';
  static const String onboardAvatar = '$_base/onboard_avatar.png';

  // First-launch tutorial
  static const String tutorialMap = '$_base/tutorial_map.png';
  static const String tutorialCreate = '$_base/tutorial_create.png';
  static const String tutorialExplore = '$_base/tutorial_explore.png';
  static const String tutorialProfile = '$_base/tutorial_profile.png';

  // Moments / states
  static const String ratingTrophy = '$_base/rating_trophy.png';
  static const String emptyNoResults = '$_base/empty_no_results.png';
  static const String emptyLonely = '$_base/empty_lonely.png';
}

/// Renders a bundled line-art illustration at a given size.
///
/// The PNGs already carry the soft-white ink + transparent background, so no
/// tinting is needed — they drop straight onto the dark theme.
class AppIllustration extends StatelessWidget {
  final String asset;
  final double? size;
  final double? width;
  final double? height;

  const AppIllustration(
    this.asset, {
    super.key,
    this.size,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: width ?? size,
      height: height ?? size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      // Decode at a sensible cap to keep memory low; 400px source art.
      cacheWidth: 800,
    );
  }
}

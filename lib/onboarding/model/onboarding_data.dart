/// Central model that holds all onboarding data collected across screens.
/// Passed between screens to accumulate user input.
class OnboardingData {
  static const String stepPassword = 'password';
  static const String stepUsername = 'username';
  static const String stepDemographics = 'demographics';
  static const String stepVibe = 'vibe';
  static const String stepBio = 'bio';
  static const String stepPhoto = 'photo';

  String? name;
  String? username;
  String? gender;
  DateTime? dob;
  String? avatarPath;
  List<String> vibes = [];
  String? bio;

  /// Returns true if the name and username fields are filled.
  bool get hasNameAndUsername =>
      (name?.trim().isNotEmpty ?? false) &&
      (username?.trim().isNotEmpty ?? false);

  /// Returns true if demographics are complete.
  bool get hasDemographics => gender != null && dob != null;

  /// Returns true if enough vibe tags have been selected.
  bool get hasEnoughVibes => vibes.length >= 3;

  /// Returns true if the bio is filled.
  bool get hasBio => (bio?.trim().isNotEmpty ?? false);
}

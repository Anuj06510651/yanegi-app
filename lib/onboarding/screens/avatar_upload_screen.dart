import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:yanegi/onboarding/auth_bootstrapper.dart';
import 'package:yanegi/onboarding/model/branding_lines.dart';
import 'package:yanegi/onboarding/model/onboarding_data.dart';
import 'package:yanegi/onboarding/widgets/onboarding_screen.dart';
import 'package:yanegi/widgets/app_illustration.dart';
import 'package:yanegi/theme/yanegi_theme.dart';
import 'package:yanegi/services/auth_service.dart';
import 'package:yanegi/services/user_service.dart';
import 'package:yanegi/onboarding/screens/bio_screen.dart';

/// Screen 4: Avatar upload with camera or gallery option.
class AvatarUploadScreen extends StatefulWidget {
  final OnboardingData data;

  const AvatarUploadScreen({super.key, required this.data});

  @override
  State<AvatarUploadScreen> createState() => _AvatarUploadScreenState();
}

class _AvatarUploadScreenState extends State<AvatarUploadScreen> {
  final ImagePicker _picker = ImagePicker();
  final UserService _userService = UserService();
  bool _hasAvatar = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _hasAvatar = widget.data.avatarPath != null;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _pickImageWithRecovery(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (image == null) return;

      setState(() {
        widget.data.avatarPath = image.path;
        _hasAvatar = true;
      });
    } catch (e) {
      debugPrint('Avatar upload pick image failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not select image. Please try again.'),
          ),
        );
      }
    }
  }

  Future<XFile?> _pickImageWithRecovery({
    required ImageSource source,
    int? maxWidth,
    int? maxHeight,
    int? imageQuality,
  }) async {
    final lostData = await _picker.retrieveLostData();
    if (lostData.files != null && lostData.files!.isNotEmpty) {
      debugPrint('Recovered lost image picker data');
      return lostData.files!.first;
    }
    if (lostData.exception != null) {
      debugPrint(
          'Image picker lost-data recovery error: ${lostData.exception}');
    }

    final file = await _picker.pickImage(
      source: source,
      maxWidth: maxWidth?.toDouble(),
      maxHeight: maxHeight?.toDouble(),
      imageQuality: imageQuality,
    );
    if (file == null) {
      debugPrint('User cancelled image selection');
      return null;
    }
    return file;
  }

  void _showPickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: YanegiColors.onbField,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(YanegiRadius.xl),
        ),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(YanegiSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: YanegiColors.onbInkFaint.withAlpha(100),
                  borderRadius: BorderRadius.circular(YanegiRadius.pill),
                ),
              ),
              const SizedBox(height: YanegiSpacing.lg),
              Text(
                'Choose Photo',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: YanegiSpacing.lg),
              _buildPickerOption(
                icon: Icons.camera_alt_rounded,
                label: 'Take a Photo',
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              const SizedBox(height: YanegiSpacing.sm),
              _buildPickerOption(
                icon: Icons.photo_library_rounded,
                label: 'Choose from Gallery',
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickerOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(YanegiRadius.md),
          color: YanegiColors.onbAccent.withAlpha(30),
        ),
        child: Icon(icon, color: YanegiColors.onbAccent, size: 22),
      ),
      title: Text(
        label,
        style: const TextStyle(
          color: YanegiColors.onbInk,
          fontSize: 16,
        ),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(YanegiRadius.md),
      ),
    );
  }

  Future<void> _onNext() async {
    if (_isSaving) return;

    if (!_hasAvatar) {
      final confirmed = await showDialog<bool>(
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
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: YanegiColors.onbAccent.withAlpha(25),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: YanegiColors.onbAccent,
                    size: 28,
                  ),
                ),
                const SizedBox(height: YanegiSpacing.md),
                const Text(
                  'Skip your profile photo?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: YanegiColors.onbInk,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: YanegiSpacing.sm),
                const Text(
                  'Profiles with photos get up to 3× more connections. You can add one later in your profile settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: YanegiColors.onbInkSoft,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: YanegiSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
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
                      'Add a Photo',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: YanegiSpacing.sm),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text(
                    'Skip for now',
                    style: TextStyle(
                      color: YanegiColors.onbInkFaint,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _isSaving = true);

    print(
        'TESTING [ONBOARDING STEP 3]: Uploading avatar & saving to Firestore');
    var didSave = false;
    try {
      await _userService.saveUser(
        name: widget.data.name ?? '',
        username: widget.data.username ?? '',
        gender: widget.data.gender,
        dob: widget.data.dob,
        avatarUrl: widget.data.avatarPath,
        vibes: widget.data.vibes,
        bio: widget.data.bio,
        onboardingStep: OnboardingData.stepPhoto,
        hasCompletedProfile: true,
      );
      didSave = true;
    } catch (e) {
      print('TESTING [ERROR]: Failed saving step 3 data (avatar): $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not complete onboarding. Please retry.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }

    if (didSave && mounted) {
      AuthBootstrapperController.rebootstrap(
        navigationContext: context,
        resetNavigation: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return OnboardingScreen(
      icon: Icons.face_rounded,
      illustration: const AppIllustration(AppIllustrations.onboardAvatar),
      title: 'Show your face',
      subtitle: 'Add a photo so people recognise you.',
      brandingLines: yanegiBrandingLines.sublist(12, 16),
      currentStep: 5,
      totalSteps: 5,
      buttonLabel: _hasAvatar ? 'Finish & explore' : 'Skip for now',
      onButtonPressed: _isSaving ? null : _onNext,
      onBack: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BioScreen(
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
      inputSection: Column(
        children: [
          _buildAvatarPicker(size),
          if (_isSaving) ...[
            const SizedBox(height: YanegiSpacing.lg),
            _buildUploadProgress(),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatarPicker(Size size) {
    return Center(
      child: GestureDetector(
        onTap: _showPickerOptions,
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            // Avatar circle
            AnimatedContainer(
              duration: YanegiDurations.standard,
              width: size.width * 0.4,
              height: size.width * 0.4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: YanegiColors.onbField.withAlpha(200),
                border: Border.all(
                  color: _hasAvatar
                      ? YanegiColors.onbAccent.withAlpha(150)
                      : YanegiColors.onbBorder.withAlpha(120),
                  width: 2,
                ),
                boxShadow: _hasAvatar
                    ? YanegiShadows.glow(YanegiColors.onbAccent, intensity: 0.3)
                    : null,
                image: _hasAvatar && widget.data.avatarPath != null
                    ? DecorationImage(
                        image: _resolveAvatarProvider(widget.data.avatarPath!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: !_hasAvatar
                  ? Icon(
                      Icons.person_rounded,
                      size: size.width * 0.15,
                      color: YanegiColors.onbInkFaint,
                    )
                  : null,
            ),

            // Camera button overlay
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [YanegiColors.onbAccent, Color(0xFFFF9A5C)],
                ),
                boxShadow:
                    YanegiShadows.glow(YanegiColors.onbAccent, intensity: 0.4),
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadProgress() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(YanegiRadius.pill),
          child: LinearProgressIndicator(
            backgroundColor: YanegiColors.onbField,
            color: YanegiColors.onbAccent,
            minHeight: 4,
          ),
        ),
        const SizedBox(height: YanegiSpacing.sm),
        Text(
          _hasAvatar ? 'Uploading your photo…' : 'Saving…',
          style: const TextStyle(
            color: YanegiColors.onbInkFaint,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  ImageProvider _resolveAvatarProvider(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return NetworkImage(path);
    }
    return FileImage(File(path));
  }
}

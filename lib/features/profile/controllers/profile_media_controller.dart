// ignore_for_file: invalid_use_of_protected_member

part of '../../../screens/profile_social_screen.dart';

extension _ProfileMediaController on _SocialProfileScreenState {
  void _syncUploadStatesFromQueue() {
    if (_currentUid.isEmpty) return;
    _profileUploadState = _mediaStorageService
        .uploadStateForStoragePath(_profileUploadStoragePath);
    _bannerUploadState = _mediaStorageService
        .uploadStateForStoragePath(_bannerUploadStoragePath);
    _syncUploadingFlag();
  }

  bool _isInProgress(UploadQueueState? state) {
    return state == UploadQueueState.queued ||
        state == UploadQueueState.uploading ||
        state == UploadQueueState.retrying;
  }

  void _syncUploadingFlag() {
    _isUploadingMedia =
        _isInProgress(_profileUploadState) || _isInProgress(_bannerUploadState);
  }

  void _onUploadStatusEvent(UploadStatusEvent event) {
    if (!mounted || _currentUid.isEmpty) return;

    final path = event.upload.storagePath;
    final isProfile = path == _profileUploadStoragePath;
    final isBanner = path == _bannerUploadStoragePath;
    if (!isProfile && !isBanner) return;

    if (isProfile) {
      _profileUploadState = event.state;
    }
    if (isBanner) {
      _bannerUploadState = event.state;
    }

    _syncUploadingFlag();
    setState(() {});

    if (event.state == UploadQueueState.success && event.downloadUrl != null) {
      unawaited(
        _onMediaUploadSuccess(
          isBanner: isBanner,
          url: event.downloadUrl!,
        ),
      );
    }
  }

  Future<void> _pickAndUploadProfileImage({required bool isBanner}) async {
    if (_isUploadingMedia || _isPickingMedia || _currentUid.isEmpty) return;
    print('Media pick triggered (isBanner=$isBanner)');
    _isPickingMedia = true;

    String? croppedPath;
    try {
      final picker = ImagePicker();
      final lostData = await picker.retrieveLostData();

      XFile? picked;
      if (lostData.files != null && lostData.files!.isNotEmpty) {
        debugPrint('Recovered lost image picker data');
        picked = lostData.files!.first;
      } else {
        if (lostData.exception != null) {
          debugPrint(
              'Image picker lost-data recovery error: ${lostData.exception}');
        }

        picked = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 70,
          maxWidth: isBanner ? 2048 : 1024,
          maxHeight: isBanner ? 1152 : 1024,
        );
        if (picked == null) {
          debugPrint('User cancelled image selection');
          return;
        }
      }

      if (!mounted) return;
      final pickedFile = picked;

      croppedPath = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => CropScreen(
            imageFile: File(pickedFile.path),
            isBanner: isBanner,
          ),
        ),
      );
      if (croppedPath == null || croppedPath.trim().isEmpty) return;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not pick image. Please try again.')),
      );
      return;
    } finally {
      _isPickingMedia = false;
    }

    if (!mounted) return;
    setState(() {
      if (isBanner) {
        _bannerUploadState = UploadQueueState.queued;
      } else {
        _profileUploadState = UploadQueueState.queued;
      }
      _syncUploadingFlag();
    });

    try {
      if (isBanner) {
        await _mediaStorageService.enqueueBannerImageUpload(
          userId: _currentUid,
          localFilePath: croppedPath,
        );
      } else {
        await _mediaStorageService.enqueueProfileImageUpload(
          userId: _currentUid,
          localFilePath: croppedPath,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isBanner ? 'Banner upload queued.' : 'Profile photo upload queued.',
          ),
        ),
      );
    } catch (e, stack) {
      debugPrint('Profile media upload failed (isBanner=$isBanner): $e');
      final isBucketIssue =
          e.toString().toLowerCase().contains('bucket unavailable');
      if (!mounted) return;
      setState(() {
        if (isBanner) {
          _bannerUploadState = UploadQueueState.failed;
        } else {
          _profileUploadState = UploadQueueState.failed;
        }
        _syncUploadingFlag();
      });
      ErrorHandler.showUserMessage(
        context,
        isBucketIssue
            ? AppErrorType.bucketUnavailable
            : AppErrorType.imageUploadFailed,
        error: e,
        stackTrace: stack,
        where: 'profile_social._uploadMedia',
      );
    }
  }

  Future<void> _onMediaUploadSuccess({
    required bool isBanner,
    required String url,
  }) async {
    if (_currentUid.isEmpty) return;

    if (mounted) {
      setState(() {
        if (isBanner) {
          _bannerImageUrl = url;
          _bannerUploadState = UploadQueueState.success;
        } else {
          _profileImageUrl = url;
          _profileUploadState = UploadQueueState.success;
        }
        _syncUploadingFlag();
      });
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUid)
          .set({
        if (isBanner) ...{
          'bannerUrl': url,
          'banner_url': url,
        } else ...{
          'photoUrl': url,
          'avatarUrl': url,
          'avatar_url': url,
        },
        'updated_at': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      await _loadProfileData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isBanner ? 'Banner updated.' : 'Profile photo updated.',
          ),
        ),
      );
    } catch (e) {
      print('Profile media Firestore update failed (isBanner=$isBanner): $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Image uploaded, but profile sync failed. Retrying later helps.'),
        ),
      );
    }
  }

  Future<void> _retryProfileMediaUpload({required bool isBanner}) async {
    final storagePath =
        isBanner ? _bannerUploadStoragePath : _profileUploadStoragePath;

    await _mediaStorageService.retryUploadByStoragePath(storagePath);
    if (!mounted) return;
    setState(() {
      if (isBanner) {
        _bannerUploadState = UploadQueueState.retrying;
      } else {
        _profileUploadState = UploadQueueState.retrying;
      }
      _syncUploadingFlag();
    });
  }

  Future<void> _removeProfileMedia({required bool isBanner}) async {
    if (_isUploadingMedia || _currentUid.isEmpty) return;
    setState(() => _isUploadingMedia = true);

    final previousUrl =
        (isBanner ? _bannerImageUrl : _profileImageUrl).toString().trim();

    try {
      if (isBanner) {
        await _mediaStorageService.deleteBannerImage(
          userId: _currentUid,
          oldDownloadUrl: previousUrl.isEmpty ? null : previousUrl,
        );
      } else {
        await _mediaStorageService.deleteProfileImage(
          userId: _currentUid,
          oldDownloadUrl: previousUrl.isEmpty ? null : previousUrl,
        );
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUid)
          .set({
        if (isBanner) ...{
          'bannerUrl': FieldValue.delete(),
          'banner_url': FieldValue.delete(),
          'bannerImage': FieldValue.delete(),
          'banner_image': FieldValue.delete(),
        } else ...{
          'photoUrl': FieldValue.delete(),
          'photoURL': FieldValue.delete(),
          'avatarUrl': FieldValue.delete(),
          'avatar_url': FieldValue.delete(),
          'profileImage': FieldValue.delete(),
          'profile_image': FieldValue.delete(),
        },
        'updated_at': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        if (isBanner) {
          _bannerImageUrl = '';
        } else {
          _profileImageUrl = '';
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(isBanner ? 'Banner removed.' : 'Profile photo removed.')),
      );
    } catch (e, stack) {
      debugPrint('Profile media remove failed (isBanner=$isBanner): $e');
      if (!mounted) return;
      ErrorHandler.showUserMessage(
        context,
        AppErrorType.imageDeleteFailed,
        error: e,
        stackTrace: stack,
        where: 'profile_social._removeProfileMedia',
      );
    } finally {
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }

  Future<void> _showMediaOptionsSheet({required bool isBanner}) async {
    if (!_isOwnProfile || _isUploadingMedia) return;

    final currentUrl =
        (isBanner ? _bannerImageUrl : _profileImageUrl).toString().trim();
    final hasImage = currentUrl.isNotEmpty;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: YanegiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasImage)
                ListTile(
                  leading: const Icon(Icons.visibility_outlined,
                      color: Colors.white),
                  title: Text(
                    isBanner ? 'View Banner' : 'View Photo',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.of(context).pop('view'),
                ),
              ListTile(
                leading: const Icon(Icons.image_outlined, color: Colors.white),
                title: Text(
                  hasImage
                      ? (isBanner ? 'Change Banner' : 'Change Photo')
                      : (isBanner ? 'Add Banner' : 'Add Photo'),
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.of(context).pop('change'),
              ),
              if (hasImage)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded,
                      color: Colors.redAccent),
                  title: Text(
                    isBanner ? 'Remove Banner' : 'Remove Photo',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () => Navigator.of(context).pop('remove'),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    if (action == 'view') {
      await AppImageViewer.open(
        context,
        imageUrl: currentUrl,
        heroTag: _mediaHeroTag(isBanner: isBanner),
        isCircular: !isBanner,
      );
    } else if (action == 'change') {
      await _pickAndUploadProfileImage(isBanner: isBanner);
    } else if (action == 'remove') {
      await _confirmAndRemoveProfileMedia(isBanner: isBanner);
    }
  }

  Object _mediaHeroTag({required bool isBanner}) {
    return isBanner
        ? 'profile_banner_${_profileUid}_$_bannerImageUrl'
        : 'profile_avatar_${_profileUid}_$_profileImageUrl';
  }

  Future<void> _handleAvatarTap() async {
    if (_isOwnProfile) {
      await _showMediaOptionsSheet(isBanner: false);
      return;
    }
    if (_profileImageUrl.trim().isEmpty) return;
    await AppImageViewer.open(
      context,
      imageUrl: _profileImageUrl,
      heroTag: _mediaHeroTag(isBanner: false),
      isCircular: true,
    );
  }

  Future<void> _handleBannerTap() async {
    if (_isOwnProfile) {
      await _showMediaOptionsSheet(isBanner: true);
      return;
    }
    if (_bannerImageUrl.trim().isEmpty) return;
    await AppImageViewer.open(
      context,
      imageUrl: _bannerImageUrl,
      heroTag: _mediaHeroTag(isBanner: true),
    );
  }

  Future<void> _confirmAndRemoveProfileMedia({required bool isBanner}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: YanegiColors.surface,
        title: Text(
          isBanner ? 'Remove banner?' : 'Remove profile photo?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          isBanner
              ? 'Your banner will be removed from your profile.'
              : 'Your profile photo will be removed.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;
    await _removeProfileMedia(isBanner: isBanner);
  }
}

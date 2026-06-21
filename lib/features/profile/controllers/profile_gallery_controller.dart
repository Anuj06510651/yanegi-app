// ignore_for_file: invalid_use_of_protected_member

part of '../../../screens/profile_social_screen.dart';

/// Hinge-style gallery feed: large photo cards interleaved with prompt cards.
///
/// Photos live at `users/{uid}.galleryPhotos` (a list of download URLs); prompts
/// live at `users/{uid}.prompts` (a list of `{question, answer}` maps). The
/// owner can add/replace/remove photos and add/edit/remove prompts inline;
/// visitors see only the populated cards with no editing affordances.
extension _ProfileGalleryController on _SocialProfileScreenState {
  // Curated Hinge-style prompt questions offered when adding a prompt.
  static const List<String> _promptQuestions = <String>[
    'A perfect day looks like…',
    'The way to win me over is…',
    'My most spontaneous moment was…',
    'I geek out on…',
    'My simple pleasures…',
    'I’ll fall for you if…',
    'Best travel story…',
    'Two truths and a lie…',
    'My go-to karaoke song…',
    'The hallmark of a good event is…',
    'You should join my events because…',
    'My ideal hangout…',
  ];

  // ─── PUBLIC: the interleaved feed ─────────────────────────────
  Widget _buildGalleryPromptFeed() {
    final photos = _galleryPhotos;
    final prompts = _prompts;

    // For the owner we always surface "add" slots so the profile feels alive
    // even when empty. Visitors only see populated cards.
    final int photoSlots =
        _isOwnProfile ? (photos.length < 3 ? 3 : photos.length + 1) : photos.length;
    final int promptSlots =
        _isOwnProfile ? (prompts.length < 2 ? 2 : prompts.length + 1) : prompts.length;

    if (!_isOwnProfile && photoSlots == 0 && promptSlots == 0) {
      return const SizedBox.shrink();
    }

    // Interleave: photo, prompt, photo, prompt, … then any remainder.
    final List<Widget> items = <Widget>[];
    final int maxLen = photoSlots > promptSlots ? photoSlots : promptSlots;
    for (int i = 0; i < maxLen; i++) {
      if (i < photoSlots) {
        items.add(_buildPhotoCard(i, i < photos.length ? photos[i] : null));
      }
      if (i < promptSlots) {
        items.add(
          _buildPromptCard(i, i < prompts.length ? prompts[i] : null),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final w in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: w,
            ),
        ],
      ),
    );
  }

  // ─── PHOTO CARD ───────────────────────────────────────────────
  Widget _buildPhotoCard(int index, String? url) {
    final hasImage = url != null && url.trim().isNotEmpty && isRemoteMediaUrl(url);

    return AspectRatio(
      aspectRatio: 4 / 5,
      child: GestureDetector(
        onTap: () {
          if (hasImage) {
            _onGalleryPhotoTap(index, url);
          } else if (_isOwnProfile) {
            _addGalleryPhoto();
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: _surfaceColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _textSecondaryColor.withAlpha(38)),
            image: hasImage
                ? DecorationImage(
                    image: CachedNetworkImageProvider(url),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: hasImage
              ? Stack(
                  children: [
                    if (_isOwnProfile)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: _circleIconButton(
                          icon: Icons.more_horiz_rounded,
                          onTap: () => _onGalleryPhotoTap(index, url),
                        ),
                      ),
                  ],
                )
              : _buildEmptyPhotoPlaceholder(),
        ),
      ),
    );
  }

  Widget _buildEmptyPhotoPlaceholder() {
    if (!_isOwnProfile) return const SizedBox.shrink();
    final uploading = _isUploadingGalleryPhoto;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (uploading)
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 42,
              color: _textSecondaryColor.withAlpha(160),
            ),
            const SizedBox(height: 10),
            Text(
              'Add photo',
              style: TextStyle(
                color: _textSecondaryColor.withAlpha(200),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _circleIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.black.withAlpha(95),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }

  // ─── PROMPT CARD ──────────────────────────────────────────────
  Widget _buildPromptCard(int index, Map<String, String>? prompt) {
    final hasPrompt = prompt != null &&
        (prompt['question'] ?? '').isNotEmpty &&
        (prompt['answer'] ?? '').isNotEmpty;

    if (!hasPrompt && !_isOwnProfile) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        if (hasPrompt) {
          if (_isOwnProfile) _editPrompt(index, prompt);
        } else if (_isOwnProfile) {
          _addPrompt();
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        decoration: BoxDecoration(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _textSecondaryColor.withAlpha(38)),
        ),
        child: hasPrompt
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (prompt['question'] ?? '').toUpperCase(),
                          style: TextStyle(
                            color: _textSecondaryColor.withAlpha(190),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      if (_isOwnProfile)
                        Icon(Icons.edit_outlined,
                            size: 15,
                            color: _textSecondaryColor.withAlpha(160)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    prompt['answer'] ?? '',
                    style: TextStyle(
                      color: _textPrimaryColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Icon(Icons.add_comment_outlined,
                      size: 20, color: _textSecondaryColor.withAlpha(180)),
                  const SizedBox(width: 10),
                  Text(
                    'Add a prompt',
                    style: TextStyle(
                      color: _textSecondaryColor.withAlpha(210),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ─── PHOTO ACTIONS ────────────────────────────────────────────
  Future<void> _addGalleryPhoto() async {
    if (!_isOwnProfile || _isUploadingGalleryPhoto || _currentUid.isEmpty) {
      return;
    }

    String? croppedPath;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1440,
        maxHeight: 1800,
      );
      if (picked == null) return;
      if (!mounted) return;

      croppedPath = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => CropScreen(
            imageFile: File(picked.path),
            isBanner: false,
          ),
        ),
      );
      if (croppedPath == null || croppedPath.trim().isEmpty) return;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not pick image. Please try again.')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isUploadingGalleryPhoto = true);

    try {
      // A stable-ish unique slot id. We avoid Random/DateTime.now in shared
      // helpers elsewhere, but here a wall-clock millis keyed path is fine and
      // keeps each upload distinct.
      final slotId = '${_galleryPhotos.length}_${croppedPath.hashCode}';
      final url = await _mediaStorageService.uploadImageReliable(
        localFilePath: croppedPath,
        storagePath: 'gallery_images/$_currentUid/$slotId.jpg',
        type: 'gallery',
      );

      final next = <String>[..._galleryPhotos, url];
      await _persistGalleryPhotos(next);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo added.')),
      );
    } catch (e, stack) {
      if (!mounted) return;
      ErrorHandler.showUserMessage(
        context,
        AppErrorType.imageUploadFailed,
        error: e,
        stackTrace: stack,
        where: 'profile_gallery._addGalleryPhoto',
      );
    } finally {
      if (mounted) setState(() => _isUploadingGalleryPhoto = false);
    }
  }

  Future<void> _onGalleryPhotoTap(int index, String url) async {
    if (!_isOwnProfile) {
      await AppImageViewer.open(context, imageUrl: url);
      return;
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.visibility_outlined, color: _textPrimaryColor),
              title: Text('View photo',
                  style: TextStyle(color: _textPrimaryColor)),
              onTap: () => Navigator.of(context).pop('view'),
            ),
            ListTile(
              leading: Icon(Icons.swap_horiz_rounded, color: _textPrimaryColor),
              title: Text('Replace photo',
                  style: TextStyle(color: _textPrimaryColor)),
              onTap: () => Navigator.of(context).pop('replace'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent),
              title: const Text('Remove photo',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () => Navigator.of(context).pop('remove'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'view') {
      await AppImageViewer.open(context, imageUrl: url);
    } else if (action == 'replace') {
      await _replaceGalleryPhoto(index);
    } else if (action == 'remove') {
      await _removeGalleryPhoto(index);
    }
  }

  Future<void> _replaceGalleryPhoto(int index) async {
    if (index < 0 || index >= _galleryPhotos.length) return;
    if (_isUploadingGalleryPhoto || _currentUid.isEmpty) return;

    String? croppedPath;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1440,
        maxHeight: 1800,
      );
      if (picked == null) return;
      if (!mounted) return;
      croppedPath = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) =>
              CropScreen(imageFile: File(picked.path), isBanner: false),
        ),
      );
      if (croppedPath == null || croppedPath.trim().isEmpty) return;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not pick image. Please try again.')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isUploadingGalleryPhoto = true);
    try {
      final slotId = '${index}_${croppedPath.hashCode}';
      final url = await _mediaStorageService.uploadImageReliable(
        localFilePath: croppedPath,
        storagePath: 'gallery_images/$_currentUid/$slotId.jpg',
        type: 'gallery',
      );
      final next = <String>[..._galleryPhotos];
      next[index] = url;
      await _persistGalleryPhotos(next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo updated.')),
      );
    } catch (e, stack) {
      if (!mounted) return;
      ErrorHandler.showUserMessage(
        context,
        AppErrorType.imageUploadFailed,
        error: e,
        stackTrace: stack,
        where: 'profile_gallery._replaceGalleryPhoto',
      );
    } finally {
      if (mounted) setState(() => _isUploadingGalleryPhoto = false);
    }
  }

  Future<void> _removeGalleryPhoto(int index) async {
    if (index < 0 || index >= _galleryPhotos.length) return;
    final next = <String>[..._galleryPhotos]..removeAt(index);
    await _persistGalleryPhotos(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Photo removed.')),
    );
  }

  Future<void> _persistGalleryPhotos(List<String> photos) async {
    // Optimistic local update so the UI reflects the change immediately even
    // before the profile stream round-trips.
    if (mounted) setState(() => _galleryPhotos = List<String>.unmodifiable(photos));
    await FirebaseFirestore.instance.collection('users').doc(_currentUid).set({
      'galleryPhotos': photos,
      'updatedAt': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ─── PROMPT ACTIONS ───────────────────────────────────────────
  Future<void> _addPrompt() async {
    if (!_isOwnProfile || _currentUid.isEmpty) return;

    final used = _prompts.map((e) => e['question']).toSet();
    final available =
        _promptQuestions.where((q) => !used.contains(q)).toList(growable: false);
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You’ve used all available prompts.')),
      );
      return;
    }

    final question = await _pickPromptQuestion(available);
    if (question == null || !mounted) return;

    final answer = await _editPromptAnswer(question: question, initial: '');
    if (answer == null || answer.trim().isEmpty || !mounted) return;

    final next = <Map<String, String>>[
      ..._prompts,
      {'question': question, 'answer': answer.trim()},
    ];
    await _persistPrompts(next);
  }

  Future<void> _editPrompt(int index, Map<String, String> prompt) async {
    if (!_isOwnProfile || index < 0 || index >= _prompts.length) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit_outlined, color: _textPrimaryColor),
              title: Text('Edit answer',
                  style: TextStyle(color: _textPrimaryColor)),
              onTap: () => Navigator.of(context).pop('edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent),
              title: const Text('Remove prompt',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () => Navigator.of(context).pop('remove'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'edit') {
      final answer = await _editPromptAnswer(
        question: prompt['question'] ?? '',
        initial: prompt['answer'] ?? '',
      );
      if (answer == null || answer.trim().isEmpty || !mounted) return;
      final next = <Map<String, String>>[..._prompts];
      next[index] = {
        'question': prompt['question'] ?? '',
        'answer': answer.trim(),
      };
      await _persistPrompts(next);
    } else if (action == 'remove') {
      final next = <Map<String, String>>[..._prompts]..removeAt(index);
      await _persistPrompts(next);
    }
  }

  Future<String?> _pickPromptQuestion(List<String> questions) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: _surfaceColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Choose a prompt',
                style: TextStyle(
                  color: _textPrimaryColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: questions.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(
                    questions[i],
                    style: TextStyle(
                      color: _textPrimaryColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(questions[i]),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<String?> _editPromptAnswer({
    required String question,
    required String initial,
  }) {
    final controller = TextEditingController(text: initial);
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: _surfaceColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        final bottom = MediaQuery.of(sheetContext).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, bottom + 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question.toUpperCase(),
                style: TextStyle(
                  color: _textSecondaryColor.withAlpha(200),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                maxLength: 180,
                style: TextStyle(
                  color: _textPrimaryColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  hintText: 'Type your answer…',
                  hintStyle: TextStyle(color: _textSecondaryColor),
                  filled: true,
                  fillColor: _bgColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: _textSecondaryColor.withAlpha(50)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: _textSecondaryColor.withAlpha(50)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: YanegiColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(sheetContext).pop(controller.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: YanegiColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _persistPrompts(List<Map<String, String>> prompts) async {
    if (mounted) {
      setState(() => _prompts = List<Map<String, String>>.unmodifiable(prompts));
    }
    await FirebaseFirestore.instance.collection('users').doc(_currentUid).set({
      'prompts': prompts,
      'updatedAt': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

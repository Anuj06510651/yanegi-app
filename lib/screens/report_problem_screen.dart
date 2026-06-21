import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/media_storage_service.dart';

class ReportProblemScreen extends StatefulWidget {
  const ReportProblemScreen({super.key});

  @override
  State<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends State<ReportProblemScreen> {
  static const List<String> _categories = [
    'app_bug',
    'chat_issue',
    'event_issue',
    'notification_issue',
    'account_issue',
    'other',
  ];

  final TextEditingController _descriptionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final MediaStorageService _mediaStorageService = MediaStorageService();

  String _category = 'app_bug';
  XFile? _selectedImage;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickScreenshot() async {
    try {
      final lostData = await _picker.retrieveLostData();
      XFile? file;

      if (lostData.files != null && lostData.files!.isNotEmpty) {
        debugPrint('Recovered lost image picker data');
        file = lostData.files!.first;
      } else {
        if (lostData.exception != null) {
          debugPrint(
              'Image picker lost-data recovery error: ${lostData.exception}');
        }
        file = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 80,
          maxWidth: 1600,
        );
        if (file == null) {
          debugPrint('User cancelled image selection');
          return;
        }
      }

      if (!mounted) return;
      setState(() => _selectedImage = file);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Could not select image. Please try again.');
    }
  }

  Future<String> _uploadScreenshotIfAny(String userId) async {
    final image = _selectedImage;
    if (image == null) return '';

    final bytes = await image.readAsBytes();
    if (bytes.isEmpty) return '';

    final storagePath =
        'reports/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';

    if (!kIsWeb) {
      final localPath = image.path.trim();
      if (localPath.isNotEmpty) {
        return _mediaStorageService.uploadImageReliable(
          localFilePath: localPath,
          storagePath: storagePath,
          type: 'report',
        );
      }
    }

    Uint8List uploadBytes = bytes;
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        quality: 70,
        format: CompressFormat.jpeg,
        minWidth: 1280,
        minHeight: 1280,
      );
      if (compressed.isNotEmpty) {
        uploadBytes = compressed;
      }
    } catch (_) {
      // Safe fallback to original bytes.
    }

    final ref = FirebaseStorage.instance.ref().child(storagePath);
    await ref.putData(
      uploadBytes,
      SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'public,max-age=31536000',
      ),
    );

    return ref.getDownloadURL();
  }

  String _extensionFromPath(String path) {
    final idx = path.lastIndexOf('.');
    if (idx == -1 || idx == path.length - 1) return 'jpg';
    return path.substring(idx + 1).toLowerCase();
  }

  String _contentTypeFromExt(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  String _deviceType() {
    if (kIsWeb) return 'web';

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  String _appVersion() {
    const fromEnv = String.fromEnvironment('APP_VERSION', defaultValue: '');
    if (fromEnv.trim().isNotEmpty) return fromEnv;
    return '1.0.0+1';
  }

  Future<Map<String, String>> _currentUserMeta() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      return const {
        'userId': '',
        'username': 'anonymous',
      };
    }

    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data() ?? const <String, dynamic>{};
    // Identity isolation: only read from the Yanegi user doc. Never fall
    // back to FirebaseAuth.displayName — that would attach the user's Google
    // account name to outgoing problem reports.
    final usernameRaw =
        (data['username'] ?? data['name'] ?? 'user').toString().trim();

    return {
      'userId': uid,
      'username': usernameRaw.startsWith('@') ? usernameRaw : '@$usernameRaw',
    };
  }

  Future<void> _submitReport() async {
    final description = _descriptionController.text.trim();

    if (description.isEmpty) {
      _showSnack('Description is required.');
      return;
    }
    if (description.length < 10) {
      _showSnack('Description must be at least 10 characters.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = await _currentUserMeta();
      final userId = user['userId'] ?? '';
      final username = user['username'] ?? 'anonymous';

      final screenshotUrl =
          userId.isEmpty ? '' : await _uploadScreenshotIfAny(userId);

      await FirebaseFirestore.instance.collection('reports').add({
        'userId': userId,
        'username': username,
        'category': _category,
        'description': description,
        'screenshotUrl': screenshotUrl,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
        'device': _deviceType(),
        'appVersion': _appVersion(),
      });

      if (!mounted) return;
      _showSnack('Report submitted successfully. Thank you!');
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      _showSnack('Could not submit report right now. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final textSecondary = scheme.onSurface.withOpacity(0.68);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        iconTheme: IconThemeData(color: scheme.onSurface),
        title: Text(
          'Report a Problem',
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: textSecondary.withOpacity(0.22)),
            ),
            child: Text(
              'Share details so we can debug quickly. Include steps, what happened, and what you expected.',
              style: TextStyle(color: textSecondary, height: 1.35),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _category,
            items: _categories
                .map(
                  (cat) => DropdownMenuItem<String>(
                    value: cat,
                    child: Text(cat),
                  ),
                )
                .toList(),
            onChanged: _isSubmitting
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _category = value);
                  },
            decoration: InputDecoration(
              labelText: 'Category',
              filled: true,
              fillColor: scheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            maxLength: 2000,
            minLines: 6,
            maxLines: 12,
            style: TextStyle(color: scheme.onSurface),
            decoration: InputDecoration(
              labelText: 'Description *',
              hintText: 'Minimum 10 characters',
              alignLabelWithHint: true,
              filled: true,
              fillColor: scheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: textSecondary.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Screenshot (optional)',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                if (_selectedImage != null)
                  FutureBuilder<Uint8List>(
                    future: _selectedImage!.readAsBytes(),
                    builder: (context, snapshot) {
                      final bytes = snapshot.data;
                      if (bytes == null) {
                        return Container(
                          height: 120,
                          alignment: Alignment.center,
                          child:
                              const CircularProgressIndicator(strokeWidth: 2),
                        );
                      }
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          bytes,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      );
                    },
                  )
                else
                  Text(
                    'No screenshot selected',
                    style: TextStyle(color: textSecondary),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isSubmitting ? null : _pickScreenshot,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose image'),
                    ),
                    if (_selectedImage != null)
                      TextButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => setState(() => _selectedImage = null),
                        child: const Text('Remove'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submitReport,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bug_report_outlined),
              label: Text(_isSubmitting ? 'Submitting...' : 'Submit report'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

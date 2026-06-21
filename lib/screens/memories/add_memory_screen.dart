import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/memory_service.dart';
import '../../theme/yanegi_theme.dart';

class AddMemoryScreen extends StatefulWidget {
  const AddMemoryScreen({super.key});

  @override
  State<AddMemoryScreen> createState() => _AddMemoryScreenState();
}

class _AddMemoryScreenState extends State<AddMemoryScreen> {
  final MemoryService _memoryService = MemoryService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();

  List<Map<String, dynamic>> _events = [];
  Map<String, dynamic>? _selectedEvent;
  File? _imageFile;
  bool _saving = false;
  bool _loadingEvents = true;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  @override
  void dispose() {
    _captionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    if (_uid.isEmpty) {
      setState(() => _loadingEvents = false);
      return;
    }

    final events = await _memoryService.getUserJoinedEvents(_uid);
    if (!mounted) return;
    setState(() {
      _events = events;
      if (_events.isNotEmpty) _selectedEvent = _events.first;
      _loadingEvents = false;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final lostData = await _picker.retrieveLostData();
      XFile? picked;

      if (lostData.files != null && lostData.files!.isNotEmpty) {
        debugPrint('Recovered lost image picker data');
        picked = lostData.files!.first;
      } else {
        if (lostData.exception != null) {
          debugPrint(
              'Image picker lost-data recovery error: ${lostData.exception}');
        }
        picked = await _picker.pickImage(source: source, imageQuality: 85);
        if (picked == null) {
          debugPrint('User cancelled image selection');
          return;
        }
      }

      if (!mounted) return;
      final pickedFile = picked;
      setState(() => _imageFile = File(pickedFile.path));
    } catch (e) {
      if (!mounted) return;
      _toast('Could not select image. Please try again.');
      debugPrint('AddMemoryScreen image pick failed: $e');
    }
  }

  Future<void> _submit() async {
    if (_selectedEvent == null) {
      _toast('Please select an event.');
      return;
    }
    if (_imageFile == null) {
      _toast('Please upload an image.');
      return;
    }

    setState(() => _saving = true);
    try {
      final taggedUsers = _tagsController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final created = await _memoryService.createMemory(
        eventId: (_selectedEvent!['id'] ?? '').toString(),
        eventTitle: (_selectedEvent!['title'] ?? 'Event').toString(),
        description: _captionController.text.trim(),
        imageFile: _imageFile,
        taggedUsers: taggedUsers,
      );

      if (!mounted) return;
      if (created != null) {
        Navigator.of(context).pop(true);
      } else {
        _toast('Failed to add memory. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: YanegiColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'Add Memory',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
        body: _loadingEvents
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Event',
                      style: TextStyle(
                        color: YanegiColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildEventDropdown(),
                    const SizedBox(height: 16),
                    const Text(
                      'Image',
                      style: TextStyle(
                        color: YanegiColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildImagePicker(),
                    const SizedBox(height: 16),
                    _buildField(
                      controller: _captionController,
                      label: 'Caption',
                      hint: 'Write a short caption',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    _buildField(
                      controller: _tagsController,
                      label: 'Tag users',
                      hint: 'alice, bob, charlie',
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: YanegiColors.primary,
                          disabledBackgroundColor: YanegiColors.surfaceElevated,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                'Save Memory',
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

  Widget _buildEventDropdown() {
    if (_events.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: YanegiColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'No joined events found yet.',
          style: TextStyle(color: YanegiColors.textSecondary),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: YanegiColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: (_selectedEvent?['id'] ?? '').toString(),
          dropdownColor: YanegiColors.surfaceElevated,
          isExpanded: true,
          iconEnabledColor: Colors.white,
          style: const TextStyle(color: Colors.white),
          items: _events
              .map(
                (event) => DropdownMenuItem<String>(
                  value: (event['id'] ?? '').toString(),
                  child: Text((event['title'] ?? 'Event').toString()),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _selectedEvent = _events.firstWhere((e) => e['id'] == value);
            });
          },
        ),
      ),
    );
  }

  Widget _buildImagePicker() {
    return GestureDetector(
      onTap: () async {
        await showModalBottomSheet<void>(
          context: context,
          backgroundColor: YanegiColors.surface,
          builder: (context) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined,
                        color: Colors.white),
                    title: const Text('Choose from gallery',
                        style: TextStyle(color: Colors.white)),
                    onTap: () async {
                      Navigator.pop(context);
                      await _pickImage(ImageSource.gallery);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_camera_outlined,
                        color: Colors.white),
                    title: const Text('Take photo',
                        style: TextStyle(color: Colors.white)),
                    onTap: () async {
                      Navigator.pop(context);
                      await _pickImage(ImageSource.camera);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
      child: Container(
        width: double.infinity,
        height: 180,
        decoration: BoxDecoration(
          color: YanegiColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: YanegiColors.textSecondary.withAlpha(40)),
        ),
        child: _imageFile == null
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_a_photo_outlined,
                        color: YanegiColors.textSecondary, size: 32),
                    SizedBox(height: 8),
                    Text('Tap to upload image',
                        style: TextStyle(color: YanegiColors.textSecondary)),
                  ],
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(_imageFile!, fit: BoxFit.cover),
              ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: YanegiColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: YanegiColors.textSecondary),
            filled: true,
            fillColor: YanegiColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: YanegiColors.textSecondary.withAlpha(40)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: YanegiColors.textSecondary.withAlpha(40)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: YanegiColors.primary),
            ),
          ),
        ),
      ],
    );
  }
}

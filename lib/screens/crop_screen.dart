import 'dart:io';
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class CropScreen extends StatefulWidget {
  final File imageFile;
  final bool isBanner;

  const CropScreen({
    super.key,
    required this.imageFile,
    required this.isBanner,
  });

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  final CropController _cropController = CropController();
  static const double _bannerAspectRatio = 16 / 9;
  Uint8List? _imageBytes;
  bool _isLoading = true;
  bool _isCropping = false;

  @override
  void initState() {
    super.initState();
    _loadImageBytes();
  }

  Future<void> _loadImageBytes() async {
    try {
      final bytes = await widget.imageFile.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleCropped(Uint8List croppedBytes) async {
    if (_isCropping) return;
    setState(() => _isCropping = true);

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/crop_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(croppedBytes, flush: true);

      if (!mounted) return;
      Navigator.of(context).pop(file.path);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCropping = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not crop image. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: _isCropping ? null : () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.isBanner ? 'Crop Banner' : 'Crop Profile',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          TextButton(
            onPressed: (_isLoading || _isCropping || _imageBytes == null)
                ? null
                : () => _cropController.crop(),
            child: _isCropping
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Done',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
      body: _isLoading || _imageBytes == null
          ? const Center(child: CircularProgressIndicator())
          : Crop(
              image: _imageBytes!,
              controller: _cropController,
              onCropped: _handleCropped,
              aspectRatio: widget.isBanner ? _bannerAspectRatio : 1,
              withCircleUi: false,
              baseColor: Colors.black,
              maskColor: Colors.black.withAlpha(150),
              radius: 10,
              interactive: true,
              fixCropRect: true,
              initialSize: 0.85,
              progressIndicator: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
    );
  }
}

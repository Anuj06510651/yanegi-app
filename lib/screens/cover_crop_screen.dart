import 'dart:io';
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// Full-screen cover image cropper.
///
/// The crop frame is fixed at 16:9 (fixCropRect: true). The user pans and
/// pinches the image beneath it — same behaviour as Instagram.
///
/// Returns the cropped + compressed local file path via [Navigator.pop],
/// or null if the user cancels.
class CoverCropScreen extends StatefulWidget {
  final String imagePath;

  const CoverCropScreen({super.key, required this.imagePath});

  @override
  State<CoverCropScreen> createState() => _CoverCropScreenState();
}

class _CoverCropScreenState extends State<CoverCropScreen> {
  final _cropController = CropController();

  Uint8List? _imageBytes;
  bool _isCropping = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    if (mounted) setState(() => _imageBytes = bytes);
  }

  Future<void> _onCropped(Uint8List croppedData) async {
    try {
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final outPath = '${dir.path}/cover_$ts.jpg';

      final compressed = await FlutterImageCompress.compressWithList(
        croppedData,
        minWidth: 1280,
        minHeight: 720,
        quality: 88,
        format: CompressFormat.jpeg,
      );

      await File(outPath).writeAsBytes(compressed);

      if (mounted) Navigator.pop(context, outPath);
    } catch (e) {
      debugPrint('[cover_crop] save failed: $e');
      if (mounted) {
        setState(() => _isCropping = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not save image. Please try again.')),
        );
      }
    }
  }

  Future<void> _confirmCrop() async {
    if (_isCropping) return;
    setState(() => _isCropping = true);
    _cropController.crop();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _imageBytes;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _isCropping ? null : () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: _isCropping
                            ? Colors.white.withAlpha(80)
                            : Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Cover',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _isCropping ? null : _confirmCrop,
                    child: AnimatedOpacity(
                      opacity: _isCropping ? 0.6 : 1.0,
                      duration: const Duration(milliseconds: 150),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: _isCropping
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Text(
                                'Use',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Hint ──
            Text(
              'Pinch to zoom  ·  Drag to reposition',
              style: TextStyle(
                color: Colors.white.withAlpha(110),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            // ── Crop widget ──
            Expanded(
              child: bytes == null
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF3B82F6),
                      ),
                    )
                  : Crop(
                      image: bytes,
                      controller: _cropController,
                      onCropped: _onCropped,
                      aspectRatio: 16 / 9,
                      interactive: true,
                      fixCropRect: true,
                      baseColor: Colors.black,
                      maskColor: Colors.black.withOpacity(0.55),
                    ),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

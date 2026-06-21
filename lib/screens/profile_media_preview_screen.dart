import 'dart:io';

import 'package:flutter/material.dart';

import 'crop_screen.dart';

class ProfileMediaPreviewScreen extends StatelessWidget {
  final String initialPath;
  final bool isBanner;

  const ProfileMediaPreviewScreen({
    super.key,
    required this.initialPath,
    required this.isBanner,
  });

  @override
  Widget build(BuildContext context) {
    return CropScreen(
      imageFile: File(initialPath),
      isBanner: isBanner,
    );
  }
}

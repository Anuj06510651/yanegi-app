import 'package:flutter/material.dart';
import 'package:yanegi/theme/yanegi_theme.dart';

class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({
    super.key,
    required this.title,
    required this.message,
    this.imageUrl,
  });

  final String title;
  final String message;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final safeImageUrl = imageUrl?.trim();
    final hasImage = safeImageUrl != null && safeImageUrl.isNotEmpty;

    return Scaffold(
      backgroundColor: YanegiColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (hasImage)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.network(
                      safeImageUrl,
                      height: 220,
                      width: 220,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _fallbackIcon(),
                    ),
                  )
                else
                  _fallbackIcon(),
                const SizedBox(height: 24),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 24,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallbackIcon() {
    return Container(
      height: 220,
      width: 220,
      decoration: BoxDecoration(
        color: YanegiColors.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: YanegiColors.primary.withOpacity(0.35),
          width: 1.3,
        ),
      ),
      child: const Icon(
        Icons.construction_rounded,
        size: 80,
        color: YanegiColors.primary,
      ),
    );
  }
}

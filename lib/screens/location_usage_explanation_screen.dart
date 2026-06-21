import 'package:flutter/material.dart';

class LocationUsageExplanationScreen extends StatelessWidget {
  const LocationUsageExplanationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        iconTheme: IconThemeData(color: scheme.onSurface),
        title: Text(
          'Location Usage',
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Center(
        child: Text(
          'Coming Soon',
          style: TextStyle(
            color: scheme.onSurface.withOpacity(0.68),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

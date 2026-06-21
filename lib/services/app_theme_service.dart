import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeService {
  AppThemeService._();

  static final AppThemeService instance = AppThemeService._();
  static const String _localThemeModeKey = 'app_theme_mode';

  final ValueNotifier<ThemeMode> _themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  ValueNotifier<ThemeMode> get themeModeListenable => _themeModeNotifier;

  ThemeMode get currentMode => _themeModeNotifier.value;

  String get currentLabel => _labelFromMode(currentMode);

  Future<void> loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final localStored = prefs.getString(_localThemeModeKey);
    if (localStored != null) {
      _themeModeNotifier.value = _modeFromStored(localStored);
    }

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      return;
    }

    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    final data = doc.data() ?? const <String, dynamic>{};
    final stored = (data['theme'] ?? data['themeMode'] ?? '').toString();
    if (stored.isNotEmpty) {
      _themeModeNotifier.value = _modeFromStored(stored);
      if (stored != localStored) {
        await prefs.setString(_localThemeModeKey, stored);
      }
    }
  }

  Future<void> setThemeLabel(String label) async {
    final mode = _modeFromLabel(label);
    await setThemeMode(mode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeModeNotifier.value = mode;
    final stored = _storedFromMode(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localThemeModeKey, stored);

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'theme': stored,
      'themeMode': stored,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static ThemeMode _modeFromStored(String raw) {
    final value = raw.trim().toLowerCase();
    switch (value) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  static ThemeMode _modeFromLabel(String label) {
    final value = label.trim().toLowerCase();
    switch (value) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  static String _storedFromMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static String _labelFromMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }
}

import 'package:flutter/material.dart';
import 'dart:ui';

/// Yanegi Design System
/// A premium dark theme with intelligent glow accents and fluid motion

class YanegiColors {
  YanegiColors._();

  // Core colors from design system
  static const Color primary = Color(0xFF3B82F6); // Primary Orange
  static const Color secondary = Color(0xFF204A63); // Secondary Dark Blue
  static const Color tertiary = Color(0xFFFFC615); // Tertiary Golden Yellow
  static const Color neutral = Color(0xFF7F7F7F); // Neutral Gray

  // Background elevation system
  static const Color background = Color(0xFF000000); // Level 0 — void black
  static const Color surface = Color(0xFF0C0C0C); // Level 1
  static const Color surfaceElevated = Color(0xFF161616); // Level 2
  static const Color surfaceGlass = Color(0xFF1A1A28); // Glass dark

  // Text hierarchy with warm neutrals
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFADADAD);
  static const Color textTertiary = Color(0xFF999999);

  // Accent colors based on the palette
  static const Color accentPrimary = Color(0xFF3B82F6); // Primary Orange
  static const Color accentSecondary = Color(0xFF204A63); // Secondary Blue
  static const Color accentTertiary = Color(0xFFFFC615); // Golden Yellow
  static const Color accentSuccess =
      Color(0xFF34D399); // Keep green for success

  // Glow colors with controlled opacity
  static Color glowPrimary = primary.withAlpha(102); // 0.4 * 255
  static Color glowSecondary = secondary.withAlpha(102); // 0.4 * 255
  static Color glowTertiary = tertiary.withAlpha(89); // 0.35 * 255

  // Map specific using secondary as base
  static const Color mapDark = Color(0xFF050505);
  static const Color mapGrid = Color(0xFF1A1A28);
  static const Color nodeInactive = Color(0xFF374955);

  // Legacy colors for backward compatibility
  static const Color accentCyan = Color(0xFF3B82F6); // Map to primary
  static const Color accentViolet = Color(0xFF204A63); // Map to secondary
  static const Color accentPink = Color(0xFFFFC615); // Map to tertiary
  static const Color accentGreen = Color(0xFF34D399); // Keep green

  static Color glowCyan = glowPrimary;
  static Color glowViolet = glowSecondary;
  static Color glowPink = glowTertiary;

  // Onboarding light palette (Hinge-style warm, clean light surfaces)
  static const Color onbBg = Color(0xFFF7F5F0); // warm cream background
  static const Color onbBgSoft = Color(0xFFFBFAF7); // near-white gradient stop
  static const Color onbInk = Color(0xFF1E2A36); // primary text / ink
  static const Color onbInkSoft = Color(0xFF3D4754); // secondary text
  static const Color onbInkFaint = Color(0xFF6B7480); // tertiary / hints
  static const Color onbField = Color(0xFFFFFFFF); // input fill
  static const Color onbBorder = Color(0xFFE4E2DB); // borders / dividers

  // Onboarding accent: a slightly darker, calmer blue than [primary] so the
  // onboarding flow reads softer against the warm cream surfaces. Use this in
  // onboarding screens instead of [primary].
  static const Color onbAccent = Color(0xFF2F6FD6); // small darken of primary
  static const Color onbAccentSoft = Color(0xFF255FBF); // pressed / deeper
}

class YanegiTypeScale {
  YanegiTypeScale._();

  static const double h1 = 24;
  static const double h2 = 18;
  static const double body = 15;
  static const double label = 13;
  static const double meta = 11;

  static const TextStyle h1Style = TextStyle(
    fontSize: h1,
    fontWeight: FontWeight.w700,
    color: YanegiColors.textPrimary,
    letterSpacing: -0.2,
  );

  static const TextStyle h2Style = TextStyle(
    fontSize: h2,
    fontWeight: FontWeight.w600,
    color: YanegiColors.textPrimary,
  );

  static const TextStyle bodyStyle = TextStyle(
    fontSize: body,
    fontWeight: FontWeight.w400,
    color: YanegiColors.textPrimary,
  );

  static const TextStyle labelStyle = TextStyle(
    fontSize: label,
    fontWeight: FontWeight.w600,
    color: YanegiColors.textSecondary,
  );

  static const TextStyle metaStyle = TextStyle(
    fontSize: meta,
    fontWeight: FontWeight.w500,
    color: YanegiColors.textTertiary,
    letterSpacing: 0.3,
  );
}

class YanegiSpacing {
  YanegiSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  // Safe area padding
  static const double safeBottom = 34.0;
  static const double safeTop = 44.0;
}

class YanegiRadius {
  YanegiRadius._();

  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double pill = 100.0;
}

class YanegiDurations {
  YanegiDurations._();

  static const Duration micro = Duration(milliseconds: 150);
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration standard = Duration(milliseconds: 350);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration breathing = Duration(milliseconds: 2000);
  static const Duration pulse = Duration(milliseconds: 1500);
}

class YanegiCurves {
  YanegiCurves._();

  // Smooth, organic motion
  static const Curve smooth = Curves.easeOutCubic;
  static const Curve bounce = Curves.elasticOut;
  static const Curve spring = Curves.easeOutBack;
  static const Curve gentle = Curves.easeInOutSine;
}

class YanegiShadows {
  YanegiShadows._();

  static List<BoxShadow> glow(Color color, {double intensity = 1.0}) {
    return [
      BoxShadow(
        color: color.withAlpha((0.3 * intensity * 255).toInt()),
        blurRadius: 20 * intensity,
        spreadRadius: 2 * intensity,
      ),
      BoxShadow(
        color: color.withAlpha((0.15 * intensity * 255).toInt()),
        blurRadius: 40 * intensity,
        spreadRadius: 8 * intensity,
      ),
    ];
  }

  static List<BoxShadow> softElevation = [
    BoxShadow(
      color: Colors.black.withAlpha(76), // 0.3 * 255
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: Colors.black.withAlpha(25), // 0.1 * 255
      blurRadius: 32,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> glassElevation = [
    BoxShadow(
      color: Colors.black.withAlpha(64), // 0.25 * 255
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
}

/// Glass morphism effect container
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Border? border;

  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 20.0,
    this.backgroundColor,
    this.borderRadius,
    this.padding,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(YanegiRadius.lg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: backgroundColor ??
                YanegiColors.surfaceGlass.withAlpha(178), // 0.7 * 255
            borderRadius:
                borderRadius ?? BorderRadius.circular(YanegiRadius.lg),
            border: border ??
                Border.all(
                  color: Colors.white.withAlpha(20), // 0.08 * 255
                  width: 1,
                ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Theme data for the app
class YanegiTheme {
  static ThemeData get light {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF7F9FC),
      primaryColor: YanegiColors.primary,
      colorScheme: const ColorScheme.light(
        primary: YanegiColors.primary,
        secondary: YanegiColors.secondary,
        tertiary: YanegiColors.tertiary,
        surface: Colors.white,
        surfaceContainerHighest: Color(0xFFE8EDF3),
        error: Color(0xFFD32F2F),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onTertiary: Colors.black,
        onSurface: Color(0xFF161C22),
      ),
      fontFamily: 'SourceSans3',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontFamily: 'PlayfairDisplay',
          fontSize: YanegiTypeScale.h1,
          fontWeight: FontWeight.w800,
          color: Color(0xFF141821),
        ),
        titleLarge: TextStyle(
          fontSize: YanegiTypeScale.h2,
          fontWeight: FontWeight.w700,
          color: Color(0xFF141821),
        ),
        bodyLarge: TextStyle(
          fontSize: YanegiTypeScale.body,
          fontWeight: FontWeight.w600,
          color: Color(0xFF141821),
        ),
        bodyMedium: TextStyle(
          fontSize: YanegiTypeScale.body,
          fontWeight: FontWeight.w500,
          color: Color(0xFF2A3242),
        ),
        labelMedium: TextStyle(
          fontSize: YanegiTypeScale.label,
          fontWeight: FontWeight.w700,
          color: Color(0xFF4E5B70),
        ),
        labelSmall: TextStyle(
          fontSize: YanegiTypeScale.meta,
          fontWeight: FontWeight.w600,
          color: Color(0xFF647085),
          letterSpacing: 0.3,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF161C22),
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: YanegiColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(YanegiRadius.md),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: YanegiColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: YanegiColors.background,
      primaryColor: YanegiColors.primary,
      colorScheme: const ColorScheme.dark(
        primary: YanegiColors.primary, // Orange
        secondary: YanegiColors.secondary, // Dark Blue
        tertiary: YanegiColors.tertiary, // Golden Yellow
        surface: YanegiColors.surface,
        surfaceContainerHighest: YanegiColors.surfaceElevated,
        error: Color(0xFFFF6B6B),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onTertiary: Color(0xFF1A1A1A),
        onSurface: YanegiColors.textPrimary,
      ),
      fontFamily: 'SourceSans3',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontFamily: 'PlayfairDisplay',
          fontSize: YanegiTypeScale.h1,
          fontWeight: FontWeight.w800,
          color: YanegiColors.textPrimary,
          letterSpacing: -0.2,
        ),
        titleLarge: TextStyle(
          fontSize: YanegiTypeScale.h2,
          fontWeight: FontWeight.w700,
          color: YanegiColors.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: YanegiTypeScale.body,
          fontWeight: FontWeight.w600,
          color: YanegiColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: YanegiTypeScale.body,
          fontWeight: FontWeight.w500,
          color: YanegiColors.textSecondary,
        ),
        labelMedium: TextStyle(
          fontSize: YanegiTypeScale.label,
          fontWeight: FontWeight.w700,
          color: YanegiColors.textSecondary,
        ),
        labelSmall: TextStyle(
          fontSize: YanegiTypeScale.meta,
          fontWeight: FontWeight.w600,
          color: YanegiColors.textTertiary,
          letterSpacing: 0.3,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: YanegiColors.surface,
        foregroundColor: YanegiColors.textPrimary,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: YanegiColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(YanegiRadius.md),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: YanegiColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }
}


import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Natural Wood Color Palette and Design System Tokens
/// As specified in §4 of the Soroban technical plan.
class SorobanTheme {
  // --- Natural Wood Palette ---
  /// Frame & dividing beam (dark walnut).
  static const Color frameColor = Color(0xFF3D2B1F);

  /// Application background (warm ivory).
  static const Color backgroundColor = Color(0xFFEDE4D3);

  /// Default inactive bead color (soft muted warm sand for ghosting effect).
  static const Color beadDefaultColor = Color(0xFFE2D6C6);

  /// Inactive bead subtle outline border color.
  static const Color beadInactiveBorderColor = Color(0xFFCEBFAD);

  /// Active / Hint highlight bead color (matte warm amber).
  static const Color beadActiveColor = Color(0xFFE2A138);

  /// Active bead subtle outline border color.
  static const Color beadActiveBorderColor = Color(0xFFC78822);

  /// Accent highlight glow for chained hint animation.
  static const Color brassGlowColor = Color(0xFFFFC72C);

  /// Primary problem text and chrome elements (dark walnut ink).
  static const Color textDark = Color(0xFF2A1F17);

  /// Secondary muted text.
  static const Color textMuted = Color(0xFF7A6B5D);

  /// Rod / tiang color (subtle muted sand grey, reduces visual noise).
  static const Color rodColor = Color(0xFFD6C8B8);

  /// Unit marker dots on the beam (dots at thousands, etc.).
  static const Color beamDotColor = Color(0xFFFFFFFF);

  // --- Harmonious Per-Rod Color Palette (when toggle is ON) ---
  /// 7 balanced earthy timber hues for rods 0 through 6:
  static const List<Color> perRodColors = [
    Color(0xFF8B5E3C), // Rod 0: Terracotta
    Color(0xFFA0522D), // Rod 1: Sienna
    Color(0xFFB87333), // Rod 2: Copper
    Color(0xFFCD853F), // Rod 3: Peru
    Color(0xFF8B4513), // Rod 4: Saddle Brown
    Color(0xFFA06D42), // Rod 5: Ochre wood
    Color(0xFF704214), // Rod 6: Sepia
  ];

  // --- Typography ---
  /// Luwes & slender problem equation style (Outfit)
  static TextStyle problemEquationStyle({
    double fontSize = 24,
    FontWeight fontWeight = FontWeight.w400,
    Color color = textDark,
  }) {
    return GoogleFonts.outfit(
      textStyle: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: 0.5,
      ),
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: 0.5,
    );
  }

  /// Pudar (completed) checkpoint digit style with clear dimmed alpha
  static TextStyle problemEquationCompletedStyle({
    double fontSize = 24,
    FontWeight fontWeight = FontWeight.w400,
  }) {
    final dimmedColor = textDark.withValues(alpha: 0.22);
    return GoogleFonts.outfit(
      textStyle: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: dimmedColor,
        letterSpacing: 0.5,
      ),
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: dimmedColor,
      letterSpacing: 0.5,
    );
  }

  static const TextStyle monospaceDigitStyle = TextStyle(
    fontFamily: 'Courier',
    fontFeatures: [FontFeature.tabularFigures()],
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: textDark,
    letterSpacing: 2.0,
  );

  static const TextStyle timerStyle = TextStyle(
    fontFamily: 'Courier',
    fontFeatures: [FontFeature.tabularFigures()],
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: textDark,
  );

  static const TextStyle labelStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: textMuted,
  );

  /// Theme data for the entire Flutter application.
  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: beadDefaultColor,
        surface: backgroundColor,
      ),
      iconTheme: const IconThemeData(
        color: frameColor,
        size: 28,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: frameColor.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
          color: backgroundColor,
          fontSize: 12,
        ),
      ),
    );
  }
}

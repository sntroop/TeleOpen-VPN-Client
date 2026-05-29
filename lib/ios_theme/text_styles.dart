// lib/ios_theme/text_styles.dart
// Типографика iOS Text Styles. part of ios_theme.

part of '../ios_theme.dart';

// ════════════════════════════════════════════════════════════════════════════
// 2. ТИПОГРАФИКА (iOS Text Styles)
// ════════════════════════════════════════════════════════════════════════════

class IosTextStyles {
  final TextStyle largeTitle;  // 34 / 41 / .bold
  final TextStyle title1;      // 28 / 34 / .bold
  final TextStyle title2;      // 22 / 28 / .bold
  final TextStyle title3;      // 20 / 25 / .semibold
  final TextStyle headline;    // 17 / 22 / .semibold
  final TextStyle body;        // 17 / 22 / .regular
  final TextStyle callout;     // 16 / 21 / .regular
  final TextStyle subheadline; // 15 / 20 / .regular
  final TextStyle footnote;    // 13 / 18 / .regular
  final TextStyle caption1;    // 12 / 16 / .regular
  final TextStyle caption2;    // 11 / 13 / .regular

  IosTextStyles._(Color baseColor)
      : largeTitle = TextStyle(
          fontSize: 34, height: 41 / 34,
          fontWeight: FontWeight.w700, letterSpacing: 0.37,
          color: baseColor, fontFamily: _systemFont,
        ),
        title1 = TextStyle(
          fontSize: 28, height: 34 / 28,
          fontWeight: FontWeight.w700, letterSpacing: 0.36,
          color: baseColor, fontFamily: _systemFont,
        ),
        title2 = TextStyle(
          fontSize: 22, height: 28 / 22,
          fontWeight: FontWeight.w700, letterSpacing: 0.35,
          color: baseColor, fontFamily: _systemFont,
        ),
        title3 = TextStyle(
          fontSize: 20, height: 25 / 20,
          fontWeight: FontWeight.w600, letterSpacing: 0.38,
          color: baseColor, fontFamily: _systemFont,
        ),
        headline = TextStyle(
          fontSize: 17, height: 22 / 17,
          fontWeight: FontWeight.w600, letterSpacing: -0.41,
          color: baseColor, fontFamily: _systemFont,
        ),
        body = TextStyle(
          fontSize: 17, height: 22 / 17,
          fontWeight: FontWeight.w400, letterSpacing: -0.41,
          color: baseColor, fontFamily: _systemFont,
        ),
        callout = TextStyle(
          fontSize: 16, height: 21 / 16,
          fontWeight: FontWeight.w400, letterSpacing: -0.32,
          color: baseColor, fontFamily: _systemFont,
        ),
        subheadline = TextStyle(
          fontSize: 15, height: 20 / 15,
          fontWeight: FontWeight.w400, letterSpacing: -0.24,
          color: baseColor, fontFamily: _systemFont,
        ),
        footnote = TextStyle(
          fontSize: 13, height: 18 / 13,
          fontWeight: FontWeight.w400, letterSpacing: -0.08,
          color: baseColor, fontFamily: _systemFont,
        ),
        caption1 = TextStyle(
          fontSize: 12, height: 16 / 12,
          fontWeight: FontWeight.w400,
          color: baseColor, fontFamily: _systemFont,
        ),
        caption2 = TextStyle(
          fontSize: 11, height: 13 / 11,
          fontWeight: FontWeight.w400, letterSpacing: 0.07,
          color: baseColor, fontFamily: _systemFont,
        );

  // На Android системный шрифт — Roboto. SF Pro есть только на iOS.
  // Для максимально близкого вида на Android можно положить SF Pro в assets
  // и установить как fontFamily. Здесь оставляю null → системный.
  static const String? _systemFont = null;
}

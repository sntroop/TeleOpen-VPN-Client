// lib/ios_theme/colors.dart
// Семантическая палитра Apple HIG (light/dark). part of ios_theme.

part of '../ios_theme.dart';

// ════════════════════════════════════════════════════════════════════════════
// 1. ЦВЕТА (Apple HIG semantic palette)
// ════════════════════════════════════════════════════════════════════════════

class IosColors {
  // Фоны (3 уровня иерархии: фон экрана → группа → элемент)
  final Color bgPrimary;       // фон Scaffold (systemGroupedBackground)
  final Color bgSecondary;     // фон карточек (secondarySystemGroupedBackground)
  final Color bgTertiary;      // фон элементов внутри карточки
  final Color bgElevated;      // модалки, шиты, диалоги

  // Текст
  final Color textPrimary;     // основной (label)
  final Color textSecondary;   // вторичный (secondaryLabel ~60%)
  final Color textTertiary;    // подписи (tertiaryLabel ~30%)
  final Color textQuaternary;  // placeholder, disabled ~18%

  // Семантические цвета iOS
  final Color blue;            // primary action
  final Color green;           // success, switch ON
  final Color red;             // destructive
  final Color orange;
  final Color yellow;
  final Color purple;
  final Color pink;

  // UI-цвета
  final Color separator;       // тонкие разделители
  final Color fill;            // .systemFill (поля, secondary buttons)
  final Color fillSecondary;   // .secondarySystemFill
  final Color fillTertiary;    // ещё светлее, для off-states

  // Тени (полупрозрачные чёрные)
  final Color shadow;

  const IosColors({
    required this.bgPrimary,
    required this.bgSecondary,
    required this.bgTertiary,
    required this.bgElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textQuaternary,
    required this.blue,
    required this.green,
    required this.red,
    required this.orange,
    required this.yellow,
    required this.purple,
    required this.pink,
    required this.separator,
    required this.fill,
    required this.fillSecondary,
    required this.fillTertiary,
    required this.shadow,
  });

  /// Создаёт копию с переопределением отдельных полей.
  IosColors copyWith({
    Color? bgPrimary, Color? bgSecondary, Color? bgTertiary, Color? bgElevated,
    Color? textPrimary, Color? textSecondary, Color? textTertiary, Color? textQuaternary,
    Color? blue, Color? green, Color? red, Color? orange, Color? yellow, Color? purple, Color? pink,
    Color? separator, Color? fill, Color? fillSecondary, Color? fillTertiary,
    Color? shadow,
  }) {
    return IosColors(
      bgPrimary: bgPrimary ?? this.bgPrimary,
      bgSecondary: bgSecondary ?? this.bgSecondary,
      bgTertiary: bgTertiary ?? this.bgTertiary,
      bgElevated: bgElevated ?? this.bgElevated,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textQuaternary: textQuaternary ?? this.textQuaternary,
      blue: blue ?? this.blue,
      green: green ?? this.green,
      red: red ?? this.red,
      orange: orange ?? this.orange,
      yellow: yellow ?? this.yellow,
      purple: purple ?? this.purple,
      pink: pink ?? this.pink,
      separator: separator ?? this.separator,
      fill: fill ?? this.fill,
      fillSecondary: fillSecondary ?? this.fillSecondary,
      fillTertiary: fillTertiary ?? this.fillTertiary,
      shadow: shadow ?? this.shadow,
    );
  }

  Map<String, dynamic> toJson() => {
    'bgPrimary': bgPrimary.toARGB32(), 'bgSecondary': bgSecondary.toARGB32(),
    'bgTertiary': bgTertiary.toARGB32(), 'bgElevated': bgElevated.toARGB32(),
    'textPrimary': textPrimary.toARGB32(), 'textSecondary': textSecondary.toARGB32(),
    'textTertiary': textTertiary.toARGB32(), 'textQuaternary': textQuaternary.toARGB32(),
    'blue': blue.toARGB32(), 'green': green.toARGB32(), 'red': red.toARGB32(),
    'orange': orange.toARGB32(), 'yellow': yellow.toARGB32(),
    'purple': purple.toARGB32(), 'pink': pink.toARGB32(),
    'separator': separator.toARGB32(), 'fill': fill.toARGB32(),
    'fillSecondary': fillSecondary.toARGB32(), 'fillTertiary': fillTertiary.toARGB32(),
    'shadow': shadow.toARGB32(),
  };

  factory IosColors.fromJson(Map<String, dynamic> j, {IosColors? fallback}) {
    final fb = fallback ?? IosColors.light;
    Color c(String k, Color def) {
      final v = j[k];
      if (v == null) return def;
      if (v is int) return Color(v);
      if (v is String) {
        var s = v.trim();
        if (s.startsWith('#')) s = s.substring(1);
        if (s.length == 6) s = 'FF$s';
        final n = int.tryParse(s, radix: 16);
        return n == null ? def : Color(n);
      }
      return def;
    }
    return IosColors(
      bgPrimary: c('bgPrimary', fb.bgPrimary),
      bgSecondary: c('bgSecondary', fb.bgSecondary),
      bgTertiary: c('bgTertiary', fb.bgTertiary),
      bgElevated: c('bgElevated', fb.bgElevated),
      textPrimary: c('textPrimary', fb.textPrimary),
      textSecondary: c('textSecondary', fb.textSecondary),
      textTertiary: c('textTertiary', fb.textTertiary),
      textQuaternary: c('textQuaternary', fb.textQuaternary),
      blue: c('blue', fb.blue),
      green: c('green', fb.green),
      red: c('red', fb.red),
      orange: c('orange', fb.orange),
      yellow: c('yellow', fb.yellow),
      purple: c('purple', fb.purple),
      pink: c('pink', fb.pink),
      separator: c('separator', fb.separator),
      fill: c('fill', fb.fill),
      fillSecondary: c('fillSecondary', fb.fillSecondary),
      fillTertiary: c('fillTertiary', fb.fillTertiary),
      shadow: c('shadow', fb.shadow),
    );
  }

  const IosColors._({
    required this.bgPrimary,
    required this.bgSecondary,
    required this.bgTertiary,
    required this.bgElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textQuaternary,
    required this.blue,
    required this.green,
    required this.red,
    required this.orange,
    required this.yellow,
    required this.purple,
    required this.pink,
    required this.separator,
    required this.fill,
    required this.fillSecondary,
    required this.fillTertiary,
    required this.shadow,
  });

  // ─── LIGHT (как на скринах из Figma) ──────────────────────────────────────
  static const light = IosColors._(
    bgPrimary:      Color(0xFFF2F2F7),
    bgSecondary:    Color(0xFFFFFFFF),
    bgTertiary:     Color(0xFFF2F2F7),
    bgElevated:     Color(0xFFFFFFFF),

    textPrimary:    Color(0xFF000000),
    textSecondary:  Color(0x993C3C43), // 60%
    textTertiary:   Color(0x4D3C3C43), // 30%
    textQuaternary: Color(0x2E3C3C43), // 18%

    blue:           Color(0xFF1C1C1E),
    green:          Color(0xFF34C759),
    red:            Color(0xFFFF3B30),
    orange:         Color(0xFFFF9500),
    yellow:         Color(0xFFFFCC00),
    purple:         Color(0xFFAF52DE),
    pink:           Color(0xFFFF2D55),

    separator:      Color(0x2E3C3C43), // 18%
    fill:           Color(0x14787880), // .systemFill ~8%
    fillSecondary:  Color(0x0F787880), // ~6%
    fillTertiary:   Color(0x0A767680), // ~4%

    shadow:         Color(0x14000000), // 8% черного
  );

  // ─── DARK (iOS systemDark) ────────────────────────────────────────────────
  static const dark = IosColors._(
    bgPrimary:      Color(0xFF000000),
    bgSecondary:    Color(0xFF1C1C1E),
    bgTertiary:     Color(0xFF2C2C2E),
    bgElevated:     Color(0xFF2C2C2E),

    textPrimary:    Color(0xFFFFFFFF),
    textSecondary:  Color(0x99EBEBF5), // 60%
    textTertiary:   Color(0x4DEBEBF5), // 30%
    textQuaternary: Color(0x2EEBEBF5), // 18%

    blue:           Color(0xFFFFFFFF),
    green:          Color(0xFF30D158),
    red:            Color(0xFFFF453A),
    orange:         Color(0xFFFF9F0A),
    yellow:         Color(0xFFFFD60A),
    purple:         Color(0xFFBF5AF2),
    pink:           Color(0xFFFF375F),

    separator:      Color(0x95545458), // ~58%
    fill:           Color(0x24787880),
    fillSecondary:  Color(0x1E787880),
    fillTertiary:   Color(0x14767680),

    shadow:         Color(0x80000000), // 50% черного
  );
}

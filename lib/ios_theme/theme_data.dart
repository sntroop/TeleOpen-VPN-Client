// lib/ios_theme/theme_data.dart
// Режим темы, радиусы, фон и сводный IosThemeData. part of ios_theme.

part of '../ios_theme.dart';

// ════════════════════════════════════════════════════════════════════════════
// 4. THEME DATA (режим, радиусы, фон, сводка)
// ════════════════════════════════════════════════════════════════════════════

enum IosThemeMode { light, dark, system }

/// Радиусы скруглений — могут быть переопределены кастомной темой.
class IosRadii {
  final double small;
  final double medium;
  final double large;
  final double xLarge;
  final double button;
  final double field;

  const IosRadii({
    this.small = 8,
    this.medium = 12,
    this.large = 14,
    this.xLarge = 22,
    this.button = 14,
    this.field = 12,
  });

  /// Один множитель на всё — для слайдера "Скругления" в редакторе.
  IosRadii scaled(double k) => IosRadii(
    small: small * k, medium: medium * k, large: large * k,
    xLarge: xLarge * k, button: button * k, field: field * k,
  );

  Map<String, dynamic> toJson() => {
    'small': small, 'medium': medium, 'large': large,
    'xLarge': xLarge, 'button': button, 'field': field,
  };

  factory IosRadii.fromJson(Map<String, dynamic> j) => IosRadii(
    small: (j['small']  as num?)?.toDouble() ?? 8,
    medium:(j['medium'] as num?)?.toDouble() ?? 12,
    large: (j['large']  as num?)?.toDouble() ?? 14,
    xLarge:(j['xLarge'] as num?)?.toDouble() ?? 22,
    button:(j['button'] as num?)?.toDouble() ?? 14,
    field: (j['field']  as num?)?.toDouble() ?? 12,
  );
}

/// Фон под Scaffold — solid / gradient / image.
class IosBackground {
  final String type; // 'solid' | 'gradient' | 'image'
  final List<Color>? gradient;
  final String? imageUrl;
  // нет полей — type='solid' и берётся colors.bgPrimary

  const IosBackground.solid() : type = 'solid', gradient = null, imageUrl = null;
  const IosBackground.gradient(this.gradient) : type = 'gradient', imageUrl = null;
  const IosBackground.image(this.imageUrl) : type = 'image', gradient = null;

  Map<String, dynamic> toJson() => {
    'type': type,
    if (gradient != null) 'gradient': gradient!.map((c) => c.toARGB32()).toList(),
    if (imageUrl != null) 'imageUrl': imageUrl,
  };

  factory IosBackground.fromJson(Map<String, dynamic> j) {
    final type = (j['type'] ?? 'solid').toString();
    if (type == 'gradient' && j['gradient'] is List) {
      return IosBackground.gradient(
        (j['gradient'] as List).map((v) => Color((v as num).toInt())).toList(),
      );
    }
    if (type == 'image' && j['imageUrl'] is String) {
      return IosBackground.image(j['imageUrl'] as String);
    }
    return const IosBackground.solid();
  }
}

class IosThemeData {
  final Brightness brightness;
  final IosColors colors;
  final IosTextStyles textStyles;
  final IosRadii radii;
  final IosBackground background;
  final String? themeName; // null = встроенная (light/dark)

  IosThemeData._(
    this.brightness,
    this.colors, {
    this.radii = const IosRadii(),
    this.background = const IosBackground.solid(),
    this.themeName,
  }) : textStyles = IosTextStyles._(colors.textPrimary);

  factory IosThemeData.light() => IosThemeData._(Brightness.light, IosColors.light);
  factory IosThemeData.dark()  => IosThemeData._(Brightness.dark,  IosColors.dark);

  /// Конструктор из кастомной темы.
  factory IosThemeData.custom({
    required Brightness brightness,
    required IosColors colors,
    IosRadii radii = const IosRadii(),
    IosBackground background = const IosBackground.solid(),
    String? name,
  }) => IosThemeData._(brightness, colors,
        radii: radii, background: background, themeName: name);
}

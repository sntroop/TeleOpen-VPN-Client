// lib/ios_theme/tokens.dart
// Геометрия: радиусы, отступы, тени, длительности. part of ios_theme.

part of '../ios_theme.dart';

// ════════════════════════════════════════════════════════════════════════════
// 3. ГЕОМЕТРИЯ (радиусы, отступы, тени, длительности)
// ════════════════════════════════════════════════════════════════════════════

class IosShapes {
  // Скругления (Apple использует "continuous" / squircle).
  // ВАЖНО: это дефолтные значения. Кастомные темы могут переопределить
  // через IosRadii в IosThemeData — компоненты сами выбирают, что брать.
  static const double radiusSmall = 8;
  static const double radiusMedium = 12;
  static const double radiusLarge = 14;
  static const double radiusXLarge = 22; // карточки на скринах
  static const double radiusButton = 14;
  static const double radiusField = 12;
  static const double radiusPill = 999;

  // continuous corner (приближение Apple squircle)
  static BorderRadius continuous(double r) => BorderRadius.all(Radius.circular(r));

  // Отступы
  static const double spacingXS = 4;
  static const double spacingS = 8;
  static const double spacingM = 12;
  static const double spacingL = 16;
  static const double spacingXL = 20;
  static const double spacing2XL = 24;
  static const double spacing3XL = 32;

  // Минимальная высота тач-зоны (Apple HIG: 44pt)
  static const double minTapTarget = 44;
}

class IosShadows {
  static List<BoxShadow> card(IosColors c) => [
        BoxShadow(
          color: c.shadow,
          blurRadius: 20,
          offset: const Offset(0, 4),
          spreadRadius: -2,
        ),
      ];

  static List<BoxShadow> elevated(IosColors c) => [
        BoxShadow(
          color: c.shadow,
          blurRadius: 30,
          offset: const Offset(0, 8),
          spreadRadius: -4,
        ),
      ];
}

class IosDurations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);

  // iOS spring-кривая (приближение)
  static const Curve spring = Curves.easeOutCubic;
  static const Curve easeOut = Curves.easeOutQuart;
}

// lib/ios_theme.dart
//
// iOS 17/18 native design language for Flutter.
// Light + Dark palettes, reusable widgets matched to Apple HIG.
//
// Использование:
//   1) Оберни приложение в IosThemeScope.
//   2) Доступ к токенам: IosTheme.of(context).colors.bgPrimary, и т.д.
//   3) Используй компоненты: IosButton, IosSwitch, IosCard, IosField, IosSegment.
//
// Переключение темы:
//   IosThemeScope.of(context).toggle();
//   IosThemeScope.of(context).setMode(IosThemeMode.dark);

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

// ════════════════════════════════════════════════════════════════════════════
// 4. THEME SCOPE (управление режимом темы)
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

class IosTheme extends InheritedWidget {
  final IosThemeData data;

  const IosTheme({
    super.key,
    required this.data,
    required super.child,
  });

  static IosThemeData of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<IosTheme>();
    assert(scope != null, 'IosTheme not found in widget tree. Wrap your app in IosThemeScope.');
    return scope!.data;
  }

  @override
  bool updateShouldNotify(IosTheme oldWidget) =>
      oldWidget.data.brightness != data.brightness ||
      oldWidget.data.themeName != data.themeName ||
      oldWidget.data.colors.bgPrimary != data.colors.bgPrimary ||
      oldWidget.data.colors.blue != data.colors.blue;
}

class IosThemeScope extends StatefulWidget {
  final Widget child;
  final IosThemeMode initialMode;
  final ValueChanged<IosThemeMode>? onModeChanged;

  const IosThemeScope({
    super.key,
    required this.child,
    this.initialMode = IosThemeMode.system,
    this.onModeChanged,
  });

  static IosThemeScopeState of(BuildContext context) {
    final state = context.findAncestorStateOfType<IosThemeScopeState>();
    assert(state != null, 'IosThemeScope not found in widget tree.');
    return state!;
  }

  @override
  State<IosThemeScope> createState() => IosThemeScopeState();
}

class IosThemeScopeState extends State<IosThemeScope> with WidgetsBindingObserver {
  late IosThemeMode _mode;
  IosThemeData? _customTheme; // если != null, перекрывает встроенные light/dark

  IosThemeMode get mode => _mode;

  // Светлая тема убрана — приложение всегда тёмное (если нет кастома)
  bool get isDark => _customTheme?.brightness == Brightness.dark
      ? true
      : (_customTheme?.brightness == Brightness.light ? false : true);

  IosThemeData? get customTheme => _customTheme;

  void setMode(IosThemeMode m) {
    if (_mode == m) return;
    setState(() => _mode = m);
    widget.onModeChanged?.call(m);
  }

  void toggle() {
    // No-op: светлой темы больше нет
  }

  /// Применить кастомную тему. null = вернуться к встроенной.
  void setCustomTheme(IosThemeData? theme) {
    setState(() => _customTheme = theme);
  }

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (_mode == IosThemeMode.system) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Приоритет: кастомная тема → встроенная dark
    final data = _customTheme ?? IosThemeData.dark();
    final dark = data.brightness == Brightness.dark;

    // Подгоняем статус-бар под тему
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness:     dark ? Brightness.dark  : Brightness.light,
      systemNavigationBarColor: data.colors.bgPrimary,
      systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    ));

    return IosTheme(
      data: data,
      child: AnimatedTheme(
        duration: IosDurations.normal,
        data: ThemeData(
          brightness: data.brightness,
          scaffoldBackgroundColor: data.colors.bgPrimary,
          fontFamily: IosTextStyles._systemFont,
          textTheme: TextTheme(
            bodyMedium: data.textStyles.body,
            bodyLarge:  data.textStyles.body,
            titleLarge: data.textStyles.title2,
          ),
          colorScheme: dark
              ? const ColorScheme.dark().copyWith(primary: data.colors.blue)
              : const ColorScheme.light().copyWith(primary: data.colors.blue),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        child: widget.child,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 5. КОМПОНЕНТЫ
// ════════════════════════════════════════════════════════════════════════════

// ─── 5.1 IosButton (Primary / Destructive / Secondary / Plain) ───────────────

enum IosButtonStyle { primary, destructive, secondary, plain }

class IosButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IosButtonStyle style;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool fullWidth;
  final bool loading;

  const IosButton({
    super.key,
    required this.label,
    this.onPressed,
    this.style = IosButtonStyle.primary,
    this.leadingIcon,
    this.trailingIcon,
    this.fullWidth = true,
    this.loading = false,
  });

  @override
  State<IosButton> createState() => _IosButtonState();
}

class _IosButtonState extends State<IosButton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this, duration: IosDurations.fast, lowerBound: 0, upperBound: 1,
  );
  late final Animation<double> _scale = Tween(begin: 1.0, end: 0.96)
      .animate(CurvedAnimation(parent: _ctrl, curve: IosDurations.easeOut));

  bool get _enabled => widget.onPressed != null && !widget.loading;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    Color bg; Color fg;
    switch (widget.style) {
      case IosButtonStyle.primary:
        bg = c.blue;
        // fg должен контрастировать с bg. В этой палитре c.blue в тёмной теме
        // равен белому, поэтому Colors.white давал белый текст на белом фоне.
        // Считаем contrast по luminance.
        fg = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
            ? Colors.white
            : Colors.black;
        break;
      case IosButtonStyle.destructive:
        bg = c.fill;
        fg = c.red;
        break;
      case IosButtonStyle.secondary:
        bg = c.fill;
        fg = c.textPrimary;
        break;
      case IosButtonStyle.plain:
        bg = Colors.transparent;
        fg = c.blue;
        break;
    }
    if (!_enabled) {
      if (widget.style == IosButtonStyle.primary) {
        bg = c.textPrimary.withValues(alpha: 0.35);
      } else {
        bg = c.fillTertiary;
        fg = fg.withValues(alpha: 0.4);
      }
    }

    final content = Row(
      mainAxisSize: widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          SizedBox(
            width: 18, height: 18,
            child: CupertinoActivityIndicator(color: fg),
          )
        else if (widget.leadingIcon != null) ...[
          Icon(widget.leadingIcon, size: 18, color: fg),
          const SizedBox(width: 8),
        ],
        if (!widget.loading)
          Text(widget.label, style: t.textStyles.headline.copyWith(color: fg)),
        if (widget.trailingIcon != null) ...[
          const SizedBox(width: 8),
          Icon(widget.trailingIcon, size: 18, color: fg),
        ],
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _enabled ? (_) => _ctrl.forward() : null,
      onTapUp:   _enabled ? (_) => _ctrl.reverse() : null,
      onTapCancel: _enabled ? () => _ctrl.reverse() : null,
      onTap: _enabled ? widget.onPressed : null,
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: IosDurations.fast,
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: IosShapes.continuous(IosShapes.radiusButton),
          ),
          child: Center(child: content),
        ),
      ),
    );
  }
}

// ─── 5.2 IosSwitch (с белой полоской «I» в положении ON) ────────────────────

class IosSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const IosSwitch({super.key, required this.value, required this.onChanged});

  @override
  State<IosSwitch> createState() => _IosSwitchState();
}

class _IosSwitchState extends State<IosSwitch> with TickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this, duration: IosDurations.fast, lowerBound: 0, upperBound: 1,
  );

  @override
  void dispose() { _press.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press.forward(),
      onTapUp:   (_) => _press.reverse(),
      onTapCancel: () => _press.reverse(),
      onTap: () => widget.onChanged(!widget.value),
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, _) {
          final pressed = _press.value;
          final thumbWidth = 28 + pressed * 6; // удлинение при нажатии — фирменная iOS-фишка
          return AnimatedContainer(
            duration: IosDurations.normal,
            curve: IosDurations.spring,
            width: 52, height: 32,
            decoration: BoxDecoration(
              color: widget.value ? c.green : (t.brightness == Brightness.dark ? c.fillSecondary : const Color(0xFFE9E9EA)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Stack(
              children: [
                AnimatedAlign(
                  duration: IosDurations.normal,
                  curve: IosDurations.spring,
                  alignment: widget.value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AnimatedContainer(
                      duration: IosDurations.fast,
                      width: thumbWidth, height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 4, offset: const Offset(0, 2),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 1, offset: const Offset(0, 3), spreadRadius: 0.5,
                          ),
                        ],
                      ),
                      // Маленькая «полоска I» внутри кружка как на скрине Figma
                      child: widget.value
                          ? Center(
                              child: Container(
                                width: 2.5, height: 11,
                                decoration: BoxDecoration(
                                  color: c.green.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── 5.3 IosCard (универсальная карточка с тенью) ────────────────────────────

class IosCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color? backgroundColor;
  final bool elevated;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Border? border;

  const IosCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.radius = IosShapes.radiusXLarge,
    this.backgroundColor,
    this.elevated = true,
    this.onTap,
    this.onLongPress,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? c.bgSecondary,
        borderRadius: IosShapes.continuous(radius),
        border: border,
        boxShadow: elevated ? IosShadows.card(c) : null,
      ),
      child: child,
    );

    final wrapped = (onTap != null || onLongPress != null)
        ? GestureDetector(
            // deferToChild: тапы на дочерние GestureDetector'ы (кнопки, звёздочки)
            // обрабатываются ими, а тап на пустое место карточки — родителем.
            // С opaque родитель забирал все тапы себе, и кнопки внутри не работали.
            behavior: HitTestBehavior.deferToChild,
            onTap: onTap,
            onLongPress: onLongPress,
            child: box,
          )
        : box;

    return margin != null ? Padding(padding: margin!, child: wrapped) : wrapped;
  }
}

// ─── 5.4 IosField (поле ввода в стиле «Value» / placeholder) ────────────────

class IosField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;          // верхний лейбл
  final String? placeholder;
  final ValueChanged<String>? onChanged;
  final TextInputType keyboardType;
  final bool obscureText;
  final int maxLines;
  final bool autofocus;

  const IosField({
    super.key,
    this.controller,
    this.label,
    this.placeholder,
    this.onChanged,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.maxLines = 1,
    this.autofocus = false,
  });

  @override
  State<IosField> createState() => _IosFieldState();
}

class _IosFieldState extends State<IosField> {
  late final FocusNode _focus;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() { _focus.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return AnimatedContainer(
      duration: IosDurations.fast,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.fill,
        borderRadius: IosShapes.continuous(IosShapes.radiusField),
        border: Border.all(
          color: _focused ? c.blue.withValues(alpha: 0.5) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.label != null) ...[
            Text(widget.label!, style: t.textStyles.footnote.copyWith(color: c.textSecondary)),
            const SizedBox(height: 2),
          ],
          TextField(
            controller: widget.controller,
            focusNode: _focus,
            autofocus: widget.autofocus,
            onChanged: widget.onChanged,
            keyboardType: widget.keyboardType,
            obscureText: widget.obscureText,
            maxLines: widget.maxLines,
            cursorColor: c.blue,
            style: t.textStyles.body,
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: widget.placeholder,
              hintStyle: t.textStyles.body.copyWith(color: c.textTertiary),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 5.5 IosSegment (pill «Item | Item | Item» с активным красным) ──────────

class IosSegmentItem {
  final String label;
  final IconData? icon;
  final bool destructive;
  const IosSegmentItem(this.label, {this.icon, this.destructive = false});
}

class IosSegment extends StatelessWidget {
  final List<IosSegmentItem> items;
  final int activeIndex;
  final ValueChanged<int> onChanged;
  final bool hasOverflow;
  final VoidCallback? onOverflowTap;

  const IosSegment({
    super.key,
    required this.items,
    required this.activeIndex,
    required this.onChanged,
    this.hasOverflow = false,
    this.onOverflowTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    final children = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      final it = items[i];
      final isActive = i == activeIndex;
      Color color;
      if (it.destructive) {
        color = c.red;
      } else if (isActive)  color = c.textPrimary;
      else                color = c.textPrimary;

      children.add(GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (it.icon != null) ...[
              Icon(it.icon, size: 16, color: color),
              const SizedBox(width: 4),
            ],
            Text(it.label, style: t.textStyles.subheadline.copyWith(color: color)),
          ]),
        ),
      ));

      // разделитель между элементами
      if (i < items.length - 1) {
        children.add(Container(
          width: 1, height: 18,
          margin: const EdgeInsets.symmetric(vertical: 8),
          color: c.separator,
        ));
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: c.bgSecondary,
        borderRadius: BorderRadius.circular(IosShapes.radiusPill),
        boxShadow: IosShadows.card(c),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...children,
          if (hasOverflow)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOverflowTap,
              child: Container(
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.fill,
                  shape: BoxShape.circle,
                ),
                child: Icon(CupertinoIcons.chevron_right, size: 16, color: c.textPrimary),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── 5.6 IosMenuItem / IosMenu (контекстное меню как на скрине Figma) ───────

enum IosMenuItemKind { regular, disabled, destructive }

class IosMenuItem {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? trailing;        // ⌘ A, > , и т.д.
  final IconData? trailingIcon;  // например chevron_right
  final IosMenuItemKind kind;
  final VoidCallback? onTap;

  const IosMenuItem({
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.trailingIcon,
    this.kind = IosMenuItemKind.regular,
    this.onTap,
  });
}

class IosMenuSection {
  final String? title;
  final List<IosMenuItem> items;
  const IosMenuSection({this.title, required this.items});
}

class IosMenu extends StatelessWidget {
  final List<IosMenuSection> sections;
  final double width;

  const IosMenu({super.key, required this.sections, this.width = 250});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    final children = <Widget>[];
    for (int sIdx = 0; sIdx < sections.length; sIdx++) {
      final sec = sections[sIdx];
      if (sec.title != null) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Text(
            sec.title!,
            style: t.textStyles.caption1.copyWith(color: c.textTertiary),
          ),
        ));
      }
      for (int i = 0; i < sec.items.length; i++) {
        children.add(_buildItem(context, sec.items[i]));
        if (i < sec.items.length - 1) {
          children.add(Container(
            margin: const EdgeInsets.only(left: 44),
            height: 0.5, color: c.separator,
          ));
        }
      }
      // separator section
      if (sIdx < sections.length - 1) {
        children.add(Container(height: 8, color: c.bgPrimary.withValues(alpha: 0.5)));
      }
    }

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: c.bgSecondary,
        borderRadius: IosShapes.continuous(IosShapes.radiusLarge),
        boxShadow: IosShadows.elevated(c),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _buildItem(BuildContext context, IosMenuItem it) {
    final t = IosTheme.of(context);
    final c = t.colors;

    Color color;
    switch (it.kind) {
      case IosMenuItemKind.regular:     color = c.textPrimary; break;
      case IosMenuItemKind.disabled:    color = c.textTertiary; break;
      case IosMenuItemKind.destructive: color = c.red; break;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: it.kind == IosMenuItemKind.disabled ? null : it.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            if (it.icon != null) ...[
              Icon(it.icon, size: 18, color: color),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(it.title, style: t.textStyles.body.copyWith(color: color)),
                  if (it.subtitle != null)
                    Text(it.subtitle!, style: t.textStyles.footnote.copyWith(color: c.textTertiary)),
                ],
              ),
            ),
            if (it.trailing != null)
              Text(it.trailing!, style: t.textStyles.subheadline.copyWith(color: c.textTertiary)),
            if (it.trailingIcon != null)
              Icon(it.trailingIcon, size: 14, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ─── 5.7 IosListSection (секция настроек как Settings.app) ──────────────────

class IosListSection extends StatelessWidget {
  final String? header;
  final String? footer;
  final List<Widget> children;

  /// Необязательный виджет, прижатый к правому краю строки заголовка
  /// (например, кнопка «···» или «Поделиться»). Рисуется только если
  /// задан [header].
  final Widget? headerTrailing;

  const IosListSection({
    super.key,
    this.header,
    this.footer,
    this.headerTrailing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    final tiles = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      tiles.add(children[i]);
      if (i < children.length - 1) {
        tiles.add(Container(
          margin: const EdgeInsets.only(left: 54),
          height: 0.5, color: c.separator,
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null) Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  header!.toUpperCase(),
                  style: t.textStyles.footnote
                      .copyWith(color: c.textSecondary, letterSpacing: -0.08),
                ),
              ),
              if (headerTrailing != null) headerTrailing!,
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: c.bgSecondary,
            borderRadius: IosShapes.continuous(IosShapes.radiusLarge),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: tiles),
        ),
        if (footer != null) Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: Text(
            footer!,
            style: t.textStyles.footnote.copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}

// ─── 5.8 IosListTile (универсальная строка списка) ──────────────────────────

class IosListTile extends StatelessWidget {
  final Widget? leading;
  final IconData? leadingIcon;
  final Color? leadingIconBg;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final String? trailingText;
  final bool showChevron;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? titleColor;

  const IosListTile({
    super.key,
    this.leading,
    this.leadingIcon,
    this.leadingIconBg,
    required this.title,
    this.subtitle,
    this.trailing,
    this.trailingText,
    this.showChevron = false,
    this.onTap,
    this.onLongPress,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    Widget? lead = leading;
    if (lead == null && leadingIcon != null) {
      final bg = leadingIconBg ?? c.fill;
      // Если подложка цветная (зелёная/красная/etc) — иконка белая.
      // Если нейтральная (серая) — иконка контрастная к фону.
      final isNeutral = bg == c.fill || bg == c.fillSecondary || bg == c.fillTertiary;
      lead = Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(
          leadingIcon,
          size: 17,
          color: isNeutral ? c.textPrimary : Colors.white,
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          if (lead != null) ...[lead, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: t.textStyles.body.copyWith(color: titleColor ?? c.textPrimary)),
                if (subtitle != null)
                  Text(subtitle!, style: t.textStyles.footnote.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
          if (trailingText != null)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(left: 8, right: 4),
                child: Text(
                  trailingText!,
                  style: t.textStyles.body.copyWith(color: c.textSecondary),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
          if (trailing != null) trailing!,
          if (showChevron) Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(CupertinoIcons.chevron_right, size: 14, color: c.textTertiary),
          ),
        ]),
      ),
    );
  }
}

// ─── 5.9 IosDialog (карточка с Title + Description + actions) ───────────────

class IosDialog extends StatelessWidget {
  final String title;
  final String? description;
  final List<Widget> content;
  final List<Widget> actions;

  const IosDialog({
    super.key,
    required this.title,
    this.description,
    this.content = const [],
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: c.bgSecondary,
          borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
          boxShadow: IosShadows.elevated(c),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: t.textStyles.headline.copyWith(fontWeight: FontWeight.w700)),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(description!, style: t.textStyles.body.copyWith(color: c.textSecondary)),
            ],
            if (content.isNotEmpty) ...[
              const SizedBox(height: 18),
              ...content,
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 18),
              ...actions.map((w) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: w,
              )),
            ],
          ],
        ),
      ),
    );
  }

  /// Удобный вызов showDialog
  static Future<T?> show<T>(BuildContext context, IosDialog dialog) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.4),
      transitionDuration: IosDurations.normal,
      pageBuilder: (_, __, ___) => Material(
        // type.transparency — не рисует фон Material, но даёт DefaultTextStyle
        // и убирает жёлтое подчёркивание "free-floating" текста под showGeneralDialog
        type: MaterialType.transparency,
        child: dialog,
      ),
      transitionBuilder: (_, anim, __, child) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween(begin: 0.95, end: 1.0)
                .animate(CurvedAnimation(parent: anim, curve: IosDurations.easeOut)),
            child: child,
          ),
        );
      },
    );
  }
}

// ─── 5.10 IosThemeToggle (готовая кнопка-переключатель Light/Dark) ──────────

class IosThemeToggle extends StatelessWidget {
  const IosThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = IosThemeScope.of(context);
    final t = IosTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: scope.toggle,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: t.colors.fill,
          shape: BoxShape.circle,
        ),
        child: Icon(
          scope.isDark ? CupertinoIcons.sun_max_fill : CupertinoIcons.moon_fill,
          size: 18, color: t.colors.textPrimary,
        ),
      ),
    );
  }
}

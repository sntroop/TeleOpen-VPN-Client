// lib/ios_theme/theme_scope.dart
// InheritedWidget темы + управление режимом (light/dark/system, кастомные темы).
// part of ios_theme.

part of '../ios_theme.dart';

// ════════════════════════════════════════════════════════════════════════════
// 4b. THEME SCOPE (внедрение темы и управление режимом)
// ════════════════════════════════════════════════════════════════════════════

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

// lib/app/teleopen_app.dart
//
// Корневой виджет приложения: настраивает тему (IosThemeScope + MaterialApp),
// поднимает AppStateScope и показывает HomeScreen. Вынесено из main.dart.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ios_theme.dart';
import '../state/app_state.dart';
import '../screens/home_screen.dart';
import '../models/theme.dart' as theme_model;
import 'deep_link_listener.dart';

class TeleOpenApp extends StatefulWidget {
  final IosThemeMode initialThemeMode;
  final SharedPreferences prefs;
  final theme_model.UserTheme? savedTheme;
  const TeleOpenApp({
    super.key,
    required this.initialThemeMode,
    required this.prefs,
    this.savedTheme,
  });

  @override
  State<TeleOpenApp> createState() => _TeleOpenAppState();
}

class _TeleOpenAppState extends State<TeleOpenApp> {
  // Глобальный ключ ScaffoldMessenger — чтобы deep-link обработчик мог
  // показать snackbar поверх любого текущего экрана.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    if (widget.savedTheme != null) {
      // Применяем после первого билда, когда IosThemeScope готов.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        IosThemeScope.of(context).setCustomTheme(
            widget.savedTheme!.toIosThemeData());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = widget.prefs;
    return IosThemeScope(
      initialMode: widget.initialThemeMode,
      onModeChanged: (m) {
        prefs.setString('theme_mode', switch (m) {
          IosThemeMode.light => 'light',
          IosThemeMode.dark  => 'dark',
          IosThemeMode.system => 'system',
        });
      },
      child: AppStateScope(
        prefs: prefs,
        child: Builder(
          builder: (ctx) {
            final t = IosTheme.of(ctx);
            final c = t.colors;
            final baseText = t.textStyles.body;
            return MaterialApp(
              title: 'TeleOpen',
              debugShowCheckedModeBanner: false,
              scaffoldMessengerKey: _messengerKey,
              theme: ThemeData(
                brightness: t.brightness,
                scaffoldBackgroundColor: c.bgPrimary,
                canvasColor: c.bgPrimary,
                textTheme: TextTheme(
                  displayLarge:  baseText, displayMedium: baseText, displaySmall:  baseText,
                  headlineLarge: baseText, headlineMedium: baseText, headlineSmall: baseText,
                  titleLarge:    t.textStyles.title2,
                  titleMedium:   t.textStyles.headline,
                  titleSmall:    t.textStyles.subheadline,
                  bodyLarge:     baseText, bodyMedium: baseText, bodySmall: t.textStyles.footnote,
                  labelLarge:    t.textStyles.headline,
                  labelMedium:   t.textStyles.footnote,
                  labelSmall:    t.textStyles.caption1,
                ),
                primaryColor: c.blue,
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
              ),
              builder: (context, child) {
                return DefaultTextStyle(
                  style: baseText,
                  child: child ?? const SizedBox.shrink(),
                );
              },
              home: DeepLinkListener(
                messengerKey: _messengerKey,
                child: const HomeScreen(),
              ),
            );
          },
        ),
      ),
    );
  }
}

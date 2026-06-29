// lib/main.dart
//
// Точка входа приложения: глобальный перехват ошибок, инициализация prefs/темы,
// запуск self-update и runApp. Раньше здесь же жили AppState, AppSettings,
// VpnStatus, AppStateScope и корневой виджет — теперь они вынесены в
// lib/state/ и lib/app/, а ниже идёт реэкспорт, чтобы существующие
// `import '.../main.dart'` в экранах продолжали видеть эти имена.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ios_theme.dart';
import 'logic/crash_log.dart';
import 'logic/updater.dart';
import 'logic/theme_storage.dart';
import 'app/teleopen_app.dart';

// ── Реэкспорт публичного состояния (совместимость с импортами экранов) ──
export 'state/app_state.dart';     // AppState, AppStateScope
export 'state/app_settings.dart';  // AppSettings
export 'state/vpn_status.dart';    // VpnStatus
export 'app/teleopen_app.dart';    // TeleOpenApp

Future<void> main() async {
  // Глобальный перехват ошибок. Без этого любое необработанное
  // исключение (особенно в async-колбэках и в EventChannel-листенерах)
  // молча роняет приложение — «краш без логов». Теперь любая ошибка
  // как минимум печатается в debug-консоль и не убивает процесс там,
  // где этого можно избежать.
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Ошибки внутри Flutter-фреймворка (build/layout/paint).
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('=== FlutterError: ${details.exception}\n${details.stack}');
      CrashLog.record(details.exception, details.stack, 'flutter');
    };

    // Ошибки из нативного слоя (PlatformDispatcher).
    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      debugPrint('=== PlatformDispatcher error: $error\n$stack');
      CrashLog.record(error, stack, 'platform');
      return true; // считаем обработанной — не валим приложение
    };

    final prefs = await SharedPreferences.getInstance();
    CrashLog.attach(prefs);

    final modeStr = prefs.getString('theme_mode') ?? 'system';
    final initialMode = switch (modeStr) {
      'light' => IosThemeMode.light,
      'dark'  => IosThemeMode.dark,
      _       => IosThemeMode.system,
    };

    // Загружаем сохранённую кастомную тему (если есть).
    final savedTheme = await ThemeStorage.load();

    // In-app self-update: запускаем фоновую проверку обновлений.
    // НЕ ожидаем — иначе UI повиснет до ответа сети. Сервис сам известит
    // подписчиков (UpdateBanner) когда найдёт новую версию.
    unawaited(UpdaterService.instance.init());

    runApp(TeleOpenApp(
      initialThemeMode: initialMode,
      prefs: prefs,
      savedTheme: savedTheme,
    ));
  }, (Object error, StackTrace stack) {
    // Сюда попадают все необработанные async-исключения.
    debugPrint('=== UNCAUGHT (zone): $error\n$stack');
    CrashLog.record(error, stack, 'zone');
  });
}

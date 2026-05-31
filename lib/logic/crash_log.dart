// lib/logic/crash_log.dart
//
// Простой персистентный лог ошибок Dart-слоя.
//
// Зачем: при разработке без adb нет доступа к logcat, а необработанное
// исключение роняет приложение «без логов». Этот логгер складывает
// последние ошибки в SharedPreferences, чтобы их можно было прочитать
// прямо в приложении (экран логов) уже ПОСЛЕ перезапуска после краша.

import 'package:shared_preferences/shared_preferences.dart';

class CrashLog {
  static const _key = 'dart_crash_log';
  static const _maxEntries = 150;

  static SharedPreferences? _prefs;

  /// Вызвать один раз на старте (в main, после получения prefs).
  static void attach(SharedPreferences prefs) {
    _prefs = prefs;
  }

  /// Записать ошибку. Безопасно вызывать из любого обработчика —
  /// сам метод никогда не бросает.
  static void record(Object error, [StackTrace? stack, String? tag]) {
    try {
      final p = _prefs;
      if (p == null) return;
      final now = DateTime.now().toIso8601String();
      final head = tag != null ? '[$tag] ' : '';
      final entry = '$now $head$error'
          '${stack != null ? '\n$stack' : ''}';

      final list = p.getStringList(_key) ?? <String>[];
      list.add(entry);
      // оставляем только последние _maxEntries записей
      final trimmed = list.length > _maxEntries
          ? list.sublist(list.length - _maxEntries)
          : list;
      p.setStringList(_key, trimmed);
    } catch (_) {
      // логгер не имеет права ронять приложение
    }
  }

  /// Информационная запись (не ошибка) — для диагностики пути подключения.
  /// Пишется в тот же лог, что и краши, виден на экране «Краши приложения».
  static void note(String tag, String message) {
    try {
      final p = _prefs;
      if (p == null) return;
      final now = DateTime.now().toIso8601String();
      final entry = '$now [$tag] $message';

      final list = p.getStringList(_key) ?? <String>[];
      list.add(entry);
      final trimmed = list.length > _maxEntries
          ? list.sublist(list.length - _maxEntries)
          : list;
      p.setStringList(_key, trimmed);
    } catch (_) {
      // логгер не имеет права ронять приложение
    }
  }

  /// Прочитать весь лог одной строкой (новые записи снизу).
  static String dump() {
    try {
      final list = _prefs?.getStringList(_key) ?? const <String>[];
      if (list.isEmpty) return '(Dart-крашей не зафиксировано)';
      return list.join('\n\n──────────\n\n');
    } catch (e) {
      return 'Ошибка чтения crash-лога: $e';
    }
  }

  /// Очистить лог.
  static void clear() {
    try {
      _prefs?.remove(_key);
    } catch (_) {}
  }

  static bool get isEmpty =>
      (_prefs?.getStringList(_key) ?? const []).isEmpty;
}

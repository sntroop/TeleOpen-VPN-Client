import 'package:shared_preferences/shared_preferences.dart';

class CrashLog {
  static const _key = 'dart_crash_log';
  static const _maxEntries = 50;

  static SharedPreferences? _prefs;

  
  static void attach(SharedPreferences prefs) {
    _prefs = prefs;
  }

  
  
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
      
      final trimmed = list.length > _maxEntries
          ? list.sublist(list.length - _maxEntries)
          : list;
      p.setStringList(_key, trimmed);
    } catch (_) {
      
    }
  }

  
  
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
      
    }
  }

  
  static String dump() {
    try {
      final list = _prefs?.getStringList(_key) ?? const <String>[];
      if (list.isEmpty) return '(Dart-крашей не зафиксировано)';
      return list.join('\n\n──────────\n\n');
    } catch (e) {
      return 'Ошибка чтения crash-лога: $e';
    }
  }

  
  static void clear() {
    try {
      _prefs?.remove(_key);
    } catch (_) {}
  }

  static bool get isEmpty =>
      (_prefs?.getStringList(_key) ?? const []).isEmpty;
}

// lib/logic/theme_storage.dart
//
// Сохранение/загрузка активной кастомной темы в SharedPreferences.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/theme.dart';
import 'crash_log.dart';

const String kPrefsThemeKey = 'custom_theme_json';

class ThemeStorage {
  /// Загружает сохранённую тему или null, если её нет / поврежена.
  static Future<UserTheme?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kPrefsThemeKey);
      if (raw == null || raw.isEmpty) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return UserTheme.fromJson(j);
    } catch (e, st) {
      // Повреждённый/несовместимый JSON темы: не валим запуск, откатываемся
      // к встроенной теме, но фиксируем для разбора.
      CrashLog.record(e, st, 'theme.load');
      return null;
    }
  }

  static Future<void> save(UserTheme theme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefsThemeKey, jsonEncode(theme.toJson()));
  }

  /// Сбросить к встроенной dark.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kPrefsThemeKey);
  }
}

// lib/state/app_state_user.dart
//
// Пользователь (Telegram), JWT-токен (через защищённое хранилище) и
// per-app proxy настройки. part of app_state.

part of 'app_state.dart';

mixin AppStateUser on AppStateBase {
  void _loadUser() {
    final s = prefs.getString('tg_user');
    if (s == null || s.isEmpty) return;
    try {
      currentUser = TgUser.fromJson((jsonDecode(s) as Map).cast<String, dynamic>());
      // JWT восстанавливаем из защищённого хранилища (async, с миграцией
      // старого токена из prefs). До его загрузки запросы к маркету просто
      // пойдут без авторизации — UI обновится, когда токен подтянется.
      // ignore: discarded_futures
      _restoreJwt();
    } catch (e, st) {
      // Битый профиль в prefs — не валим запуск, но фиксируем для разбора.
      CrashLog.record(e, st, 'user.load');
    }
  }

  /// Переносит старый plaintext-JWT из SharedPreferences в Keystore/Keychain
  /// (одноразовая миграция) и восстанавливает токен в MarketApi.
  Future<void> _restoreJwt() async {
    try {
      final legacy = prefs.getString('jwt');
      if (legacy != null && legacy.isNotEmpty) {
        await SecureStore.writeJwt(legacy);
        await prefs.remove('jwt');
      }
      final jwt = await SecureStore.readJwt();
      if (jwt != null && jwt.isNotEmpty) {
        MarketApi.setJwt(jwt);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('AppState._restoreJwt: $e');
    }
  }

  void setUser(TgUser u, {String? jwt}) {
    currentUser = u;
    prefs.setString('tg_user', jsonEncode(u.toJson()));
    if (jwt != null && jwt.isNotEmpty) {
      MarketApi.setJwt(jwt);
      // ignore: discarded_futures
      SecureStore.writeJwt(jwt);
    }
    notifyListeners();
  }

  void logout() {
    currentUser = null;
    prefs.remove('tg_user');
    MarketApi.setJwt(null);
    // ignore: discarded_futures
    SecureStore.deleteJwt();
    notifyListeners();
  }

  void setPerAppProxy(PerAppProxySettings s) {
    perApp = s;
    prefs.setString('per_app_proxy', jsonEncode(s.toJson()));
    // Профили запуска виджета несут per-app список — пересобираем.
    syncWidgets();
    notifyListeners();
  }

  // ── Split-tunnel пресеты ─────────────────────────────────────────────────
  // Именованные наборы пакетов (allowlist), применяются одним тапом.

  static const _kPresetsKey = 'per_app_presets';

  /// Загрузка при старте: если ключа нет — засеваем встроенными пресетами.
  void _loadPerAppPresets() {
    final raw = prefs.getString(_kPresetsKey);
    if (raw == null) {
      perAppPresets = PerAppPreset.defaults();
      _savePerAppPresets();
      return;
    }
    perAppPresets = PerAppPreset.decode(raw);
  }

  void _savePerAppPresets() {
    prefs.setString(_kPresetsKey, PerAppPreset.encode(perAppPresets));
  }

  /// Добавить/обновить пресет (по имени). Встроенные не дублируются.
  void savePerAppPreset(PerAppPreset preset) {
    final i = perAppPresets.indexWhere((p) => p.name == preset.name);
    if (i >= 0) {
      perAppPresets[i] = preset;
    } else {
      perAppPresets = [...perAppPresets, preset];
    }
    _savePerAppPresets();
    notifyListeners();
  }

  /// Удалить пользовательский пресет (встроенные не удаляются).
  void deletePerAppPreset(String name) {
    perAppPresets =
        perAppPresets.where((p) => p.name != name || p.builtin).toList();
    _savePerAppPresets();
    notifyListeners();
  }

  /// Применить пресет → включить per-app proxy с пакетами пресета.
  void applyPerAppPreset(PerAppPreset preset) {
    setPerAppProxy(PerAppProxySettings(
      enabled: true,
      includedPackages: List<String>.from(preset.packages),
    ));
  }
}

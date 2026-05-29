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
    notifyListeners();
  }
}

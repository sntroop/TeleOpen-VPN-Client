// lib/logic/secure_store.dart
//
// Защищённое хранилище для чувствительных данных (JWT-токен авторизации).
//
// Раньше JWT лежал в SharedPreferences открытым текстом — кто угодно с
// доступом к каталогу приложения (root, бэкап, adb) мог его прочитать и
// действовать от имени пользователя. Теперь токен хранится в Android
// Keystore / iOS Keychain через flutter_secure_storage.
//
// Все методы async. Профиль пользователя (TgUser) остаётся в обычных
// prefs — он не секрет, а вот сам токен авторизации — да.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  static const _storage = FlutterSecureStorage(
    // encryptedSharedPreferences=true → данные шифруются даже на старых
    // Android, где аппаратный Keystore недоступен.
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _kJwt = 'jwt';

  static Future<String?> readJwt() => _storage.read(key: _kJwt);
  static Future<void> writeJwt(String value) =>
      _storage.write(key: _kJwt, value: value);
  static Future<void> deleteJwt() => _storage.delete(key: _kJwt);

  // ─── VPN-ноды/подписки (HIGH-5) ──────────────────────────────────────────
  // JSON-блоб всех групп с rawUri (содержат пароли/UUID). Раньше лежал в plain
  // SharedPreferences под ключом 'groups'.
  static const _kGroups = 'groups';
  static Future<String?> readGroups() => _storage.read(key: _kGroups);
  static Future<void> writeGroups(String value) =>
      _storage.write(key: _kGroups, value: value);

  // ─── Секреты настроек (HIGH-5) ───────────────────────────────────────────
  // ec_secret (секрет External Controller) и port_auth (логин:пароль прокси).
  static Future<String?> readSecret(String key) => _storage.read(key: key);
  static Future<void> writeSecret(String key, String value) =>
      _storage.write(key: key, value: value);
}

// lib/logic/trust.dart
//
// Доверие к сборке: SHA-256 сертификата, которым подписан установленный APK.
// Нативка (MainActivity.kt → метод getSigningCertSha256) читает реальный cert
// через PackageManager; здесь мы сверяем его с ожидаемым прод-значением.
//
// Зачем: TeleOpen ставится сайдлоадом (мимо Google Play). Продвинутый юзер
// может убедиться, что его APK подписан тем самым прод-ключом, а не подменён.

import 'package:flutter/services.dart';

class TrustInfo {
  /// Ожидаемый SHA-256 прод release-ключа (lowercase hex, без двоеточий).
  /// ВНИМАНИЕ: debug-сборки подписаны другим ключом → на debug будет mismatch.
  static const String expectedReleaseCertSha256 =
      'f8fc68a33ecef7accc9a51192cba45d34dc027e4615daa954b5007c9226b69b6';

  static const MethodChannel _channel =
      MethodChannel('space.teleopen.app/native');

  /// Нормализует строку cert-хэша к виду для сравнения:
  /// нижний регистр, без пробелов и двоеточий.
  static String normalize(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'[\s:]'), '');

  /// Сверяет фактический хэш с ожидаемым прод-значением.
  static bool matches(String actual) =>
      normalize(actual) == normalize(expectedReleaseCertSha256);

  /// Читает SHA-256 сертификата установленного APK через нативку.
  /// Возвращает нормализованный hex или null, если нативка недоступна/ошибка.
  static Future<String?> fetchCertSha256() async {
    try {
      final raw = await _channel.invokeMethod<String>('getSigningCertSha256');
      if (raw == null || raw.isEmpty) return null;
      return normalize(raw);
    } catch (_) {
      return null;
    }
  }
}

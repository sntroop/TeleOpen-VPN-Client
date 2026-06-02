// lib/logic/happ_keys_loader.dart
//
// Ленивая загрузка ключей Happ из assets (assets/happ/*.json) для
// logic/happ_decrypt.dart. Ключи грузятся один раз и кэшируются.
//
// Файлы собираются скриптом build_happ_assets.py:
//   assets/happ/crypt5_keys.json  = {"keys": {marker: base64(PKCS8)}}
//   assets/happ/native_keys.json  = {"keys": [base64(PKCS8), ...]}
//
// Набор ключей (marker->RSA) и алгоритм взяты из открытых проектов-дешифраторов
// Happ: LeeeeT/happ-decryptor (MIT) и amur (happ-decrypt-rs, Apache-2.0).

import 'package:flutter/services.dart' show rootBundle;

import 'happ_decrypt.dart';

HappKeys? _cached;

/// Грузит ключи Happ из assets (с кэшем). Если asset'ов нет — вернёт пустой
/// [HappKeys] (расшифровка тогда бросит HappMissingKeyException, UI покажет
/// дружелюбную ошибку).
Future<HappKeys> loadHappKeys() async {
  if (_cached != null) return _cached!;
  String? crypt5Json;
  String? nativeJson;
  try {
    crypt5Json = await rootBundle.loadString('assets/happ/crypt5_keys.json');
  } catch (_) {/* asset не подложен — оставляем null */}
  try {
    nativeJson = await rootBundle.loadString('assets/happ/native_keys.json');
  } catch (_) {/* native-ключи опциональны (нужны только для crypt..crypt4) */}
  _cached = HappKeys.fromJson(nativeJson: nativeJson, crypt5Json: crypt5Json);
  return _cached!;
}

/// Расшифровывает все happ://-ссылки в [raw], подставляя их расшифровку.
/// Строки без happ:// остаются как есть. Результат можно скормить в обычный
/// парсер подписок/нод. Если ключа нет — пробрасывает [HappMissingKeyException].
Future<String> expandHappLinks(String raw) async {
  if (!raw.contains('happ://')) return raw;
  final keys = await loadHappKeys();
  final out = <String>[];
  for (final line in raw.split('\n')) {
    final t = line.trim();
    if (isHappLink(t)) {
      out.add(decryptHappLink(t, keys).trim());
    } else {
      out.add(line);
    }
  }
  return out.join('\n');
}

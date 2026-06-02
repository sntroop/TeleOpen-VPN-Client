// lib/logic/happ_decrypt.dart
//
// Расшифровка Happ-ссылок `happ://crypt[N]/...` (crypt, crypt2..crypt5).
//
// Порт алгоритма из референса amur/src/lib.rs (happ-decrypt-rs).
// Расшифрованное тело — это обычный текст подписки (vless://..., #-метаданные
// и т.п.), который дальше уходит в существующий пайплайн parsers.dart.
//
// Схема (crypt..crypt4): RSA-PKCS1v15(privateKey[mode]) над base64-телом.
// Схема (crypt5): гибрид —
//   payload --m4831f--> inverse_m4831f --permute4--> shuffled
//   marker = shuffled[:4] + shuffled[-4:]      (выбирает RSA-ключ из 34)
//   body   = shuffled[4:-4]
//     nonce = body[:12] (12 байт ChaCha20-IETF)
//     <десятичная длина сегмента><1 байт><encSegment(base64)><rsaCiphertext(base64)>
//   rsaPlain  = RSA-PKCS1v15(priv[marker], rsaCiphertext)
//   chachaKey = base64( m4842j(rsaPlain) )                     // 32 байта
//   plain     = ChaCha20-Poly1305(chachaKey, nonce, base64(encSegment))
//   result    = base64decode( m4842j(plain) )
//
// КЛЮЧИ: 34 приватных RSA-ключа crypt5 + ключи crypt..crypt4 зашиты в самом
// приложении Happ и извлекаются из его APK (см. assets/happ/*.json). Без них
// crypt5/crypt..crypt4 расшифровать нельзя (RSA — нужен приватный ключ).
//
// NB: требует пакетов pointycastle + asn1lib (см. pubspec). Крипто-обвязка
// (RSA/PKCS8/ChaCha20-Poly1305) проверяется тестом после `flutter pub get`.

import 'dart:convert';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:pointycastle/export.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Ошибки
// ════════════════════════════════════════════════════════════════════════════

class HappDecryptException implements Exception {
  final String message;
  HappDecryptException(this.message);
  @override
  String toString() => 'HappDecryptException: $message';
}

/// Нет приватного ключа под данный crypt5-маркер (ключи не извлечены из APK).
class HappMissingKeyException extends HappDecryptException {
  final String marker;
  HappMissingKeyException(this.marker)
      : super('нет crypt5-ключа для маркера "$marker" '
            '(ключи не извлечены из Happ APK)');
}

// ════════════════════════════════════════════════════════════════════════════
//  Хранилище ключей
// ════════════════════════════════════════════════════════════════════════════

/// Ключи Happ. [nativeKeys] — список base64(PKCS8-DER) для crypt..crypt4
/// (индекс == номер режима 0..3). [crypt5Keys] — map "marker" -> base64(PKCS8-DER).
class HappKeys {
  final List<String> nativeKeys;
  final Map<String, String> crypt5Keys;

  const HappKeys({this.nativeKeys = const [], this.crypt5Keys = const {}});

  bool get isEmpty => nativeKeys.isEmpty && crypt5Keys.isEmpty;

  /// Грузит из JSON-строк. Формат native: {"keys":[...]}.
  /// Формат crypt5: {"keys":{"marker":"base64..."}}.
  factory HappKeys.fromJson({String? nativeJson, String? crypt5Json}) {
    final native = <String>[];
    final c5 = <String, String>{};
    if (nativeJson != null && nativeJson.trim().isNotEmpty) {
      final m = jsonDecode(nativeJson) as Map<String, dynamic>;
      for (final k in (m['keys'] as List)) {
        native.add(k as String);
      }
    }
    if (crypt5Json != null && crypt5Json.trim().isNotEmpty) {
      final m = jsonDecode(crypt5Json) as Map<String, dynamic>;
      (m['keys'] as Map<String, dynamic>).forEach((k, v) {
        c5[k] = v as String;
      });
    }
    return HappKeys(nativeKeys: native, crypt5Keys: c5);
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Перестановки (block-shuffle). Работают по байтам ASCII-строк.
// ════════════════════════════════════════════════════════════════════════════

String _shuffle(String text, int blockSize, List<int> order) {
  final b = text.codeUnits;
  final out = <int>[];
  final full = (b.length ~/ blockSize) * blockSize;
  for (var i = 0; i < full; i += blockSize) {
    for (final idx in order) {
      out.add(b[i + idx]);
    }
  }
  out.addAll(b.sublist(full)); // хвост (неполный блок) — как есть
  return String.fromCharCodes(out);
}

String m4831f(String t) => _shuffle(t, 6, const [1, 3, 5, 0, 2, 4]);
String inverseM4831f(String t) => _shuffle(t, 6, const [3, 0, 4, 1, 5, 2]);
String m4842j(String t) => _shuffle(t, 2, const [1, 0]);
String permute4(String t) => _shuffle(t, 4, const [2, 3, 0, 1]);

// ════════════════════════════════════════════════════════════════════════════
//  base64 (терпимый к urlsafe / отсутствию паддинга)
// ════════════════════════════════════════════════════════════════════════════

Uint8List _b64DecodeBytes(String text) {
  for (final cand in [text, text.replaceAll(RegExp(r'=+$'), '')]) {
    final pad = (4 - cand.length % 4) % 4;
    final padded = cand + ('=' * pad);
    try {
      return base64.decode(padded);
    } catch (_) {}
    try {
      return base64Url.decode(padded);
    } catch (_) {}
  }
  throw HappDecryptException('invalid base64');
}

String _b64DecodeText(String text) => utf8.decode(_b64DecodeBytes(text));

// ════════════════════════════════════════════════════════════════════════════
//  Разбор префикса
// ════════════════════════════════════════════════════════════════════════════

const _prefixes = <(String, int)>[
  ('happ://crypt5/', 4),
  ('happ://crypt4/', 3),
  ('happ://crypt3/', 2),
  ('happ://crypt2/', 1),
  ('happ://crypt/', 0),
];

(int, String) _parseInput(String value) {
  for (final (prefix, mode) in _prefixes) {
    if (value.startsWith(prefix)) {
      return (mode, value.substring(prefix.length));
    }
  }
  return (4, value); // без префикса трактуем как crypt5-payload (как в amur)
}

const _modeNames = ['crypt', 'crypt2', 'crypt3', 'crypt4', 'crypt5'];

bool isHappLink(String s) =>
    _prefixes.any((p) => s.trimLeft().startsWith(p.$1));

/// Информация о ссылке без расшифровки (для диагностики UI).
class HappInfo {
  final int mode;
  final String name;
  final int payloadLen;
  final String? crypt5Marker;
  HappInfo(this.mode, this.name, this.payloadLen, this.crypt5Marker);
}

HappInfo inspect(String value) {
  final (mode, payload) = _parseInput(value);
  String? marker;
  if (mode == 4) {
    final shuffled = permute4(inverseM4831f(m4831f(payload)));
    if (shuffled.length >= 8) {
      marker = shuffled.substring(0, 4) + shuffled.substring(shuffled.length - 4);
    }
  }
  return HappInfo(mode, _modeNames[mode], payload.length, marker);
}

// ════════════════════════════════════════════════════════════════════════════
//  Публичный API
// ════════════════════════════════════════════════════════════════════════════

/// Расшифровывает happ-ссылку и возвращает текст подписки.
/// Бросает [HappMissingKeyException] если нет нужного ключа.
String decryptHappLink(String value, HappKeys keys) {
  final (mode, payload) = _parseInput(value);
  if (mode == 4) {
    final step1 = m4831f(payload);
    final step2 = _decryptCrypt5Middle(step1, keys.crypt5Keys);
    final step3 = m4842j(step2);
    return _b64DecodeText(step3);
  }
  // crypt..crypt4
  if (mode >= keys.nativeKeys.length) {
    throw HappDecryptException(
        'нет native-ключа для режима ${_modeNames[mode]} (не извлечён из APK)');
  }
  final priv = _parsePkcs8(_b64DecodeBytes(keys.nativeKeys[mode]));
  return utf8.decode(_rsaDecryptPkcs1(priv, _b64DecodeBytes(payload)));
}

String _decryptCrypt5Middle(String ciphertext, Map<String, String> crypt5Keys) {
  final shuffled = permute4(inverseM4831f(ciphertext));
  if (shuffled.length < 8) {
    throw HappDecryptException('crypt5 payload too short');
  }
  final marker =
      shuffled.substring(0, 4) + shuffled.substring(shuffled.length - 4);
  final body = shuffled.substring(4, shuffled.length - 4);
  if (body.length < 13) {
    throw HappDecryptException('crypt5 body too short');
  }

  final nonce = Uint8List.fromList(body.codeUnits.sublist(0, 12));
  final rest = body.substring(12);

  var dc = 0;
  while (dc < rest.length && _isDigit(rest.codeUnitAt(dc))) {
    dc++;
  }
  if (dc == 0) {
    throw HappDecryptException('crypt5 segment length missing');
  }
  final segLen = int.parse(rest.substring(0, dc));
  final packed = rest.substring(dc);
  if (packed.length < 1 + segLen) {
    throw HappDecryptException('crypt5 segment truncated');
  }
  final encryptedSegment = packed.substring(1, 1 + segLen);
  final rsaCiphertext = packed.substring(1 + segLen);

  final encodedPriv = crypt5Keys[marker];
  if (encodedPriv == null) {
    throw HappMissingKeyException(marker);
  }

  final priv = _parsePkcs8(_b64DecodeBytes(encodedPriv));
  final rsaPlain = utf8.decode(_rsaDecryptPkcs1(priv, _b64DecodeBytes(rsaCiphertext)));
  final chachaKey = _b64DecodeBytes(m4842j(rsaPlain));
  if (chachaKey.length != 32) {
    throw HappDecryptException('crypt5 ChaCha key len ${chachaKey.length} != 32');
  }
  final encrypted = _b64DecodeBytes(encryptedSegment);
  return utf8.decode(_chacha20Poly1305Decrypt(chachaKey, nonce, encrypted));
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

// ════════════════════════════════════════════════════════════════════════════
//  RSA-PKCS1v15 + PKCS8-парсинг (pointycastle / asn1lib)
// ════════════════════════════════════════════════════════════════════════════

Uint8List _rsaDecryptPkcs1(RSAPrivateKey priv, Uint8List ciphertext) {
  final engine = PKCS1Encoding(RSAEngine())
    ..init(false, PrivateKeyParameter<RSAPrivateKey>(priv));
  return engine.process(ciphertext);
}

/// Разбор PKCS8 PrivateKeyInfo -> RSAPrivateKey.
/// PKCS8: SEQ{ INTEGER ver, SEQ{ oid, NULL }, OCTET STRING(PKCS1 RSAPrivateKey) }.
/// PKCS1: SEQ{ ver, n, e, d, p, q, dP, dQ, qInv }.
RSAPrivateKey _parsePkcs8(Uint8List der) {
  final top = ASN1Parser(der).nextObject() as ASN1Sequence;
  final pkOctet = top.elements[2] as ASN1OctetString;
  final pk1 =
      ASN1Parser(pkOctet.valueBytes()).nextObject() as ASN1Sequence;
  final n = (pk1.elements[1] as ASN1Integer).valueAsBigInteger;
  final d = (pk1.elements[3] as ASN1Integer).valueAsBigInteger;
  final p = (pk1.elements[4] as ASN1Integer).valueAsBigInteger;
  final q = (pk1.elements[5] as ASN1Integer).valueAsBigInteger;
  return RSAPrivateKey(n, d, p, q);
}

// ════════════════════════════════════════════════════════════════════════════
//  ChaCha20-Poly1305 (RFC 8439, IETF — 12-байтный nonce, пустой AAD).
//  Собрано из ChaCha7539Engine + Poly1305 во избежание версионных различий
//  высокоуровневого AEAD-API pointycastle.
// ════════════════════════════════════════════════════════════════════════════

Uint8List _chacha20Poly1305Decrypt(
    Uint8List key, Uint8List nonce, Uint8List combined) {
  if (combined.length < 16) {
    throw HappDecryptException('chacha: ciphertext too short for tag');
  }
  final ct = Uint8List.sublistView(combined, 0, combined.length - 16);
  final tag = Uint8List.sublistView(combined, combined.length - 16);

  final engine = ChaCha7539Engine()
    ..init(true, ParametersWithIV<KeyParameter>(KeyParameter(key), nonce));

  // Блок 0 -> ключ Poly1305 (первые 32 байта keystream); счётчик уходит на 1.
  final block0 = Uint8List(64);
  engine.processBytes(Uint8List(64), 0, 64, block0, 0);
  final otk = Uint8List.sublistView(block0, 0, 32);

  // Проверка MAC до расшифровки.
  final mac = _poly1305(otk, ct);
  if (!_constTimeEq(mac, tag)) {
    throw HappDecryptException('chacha20-poly1305: tag mismatch (неверный ключ?)');
  }

  // Расшифровка (счётчик уже на 1 — как требует RFC 8439).
  final out = Uint8List(ct.length);
  engine.processBytes(ct, 0, ct.length, out, 0);
  return out;
}

Uint8List _poly1305(Uint8List otk, Uint8List ct) {
  final poly = Poly1305()..init(KeyParameter(otk));
  // AAD пустой.
  poly.update(ct, 0, ct.length);
  final padCt = (16 - ct.length % 16) % 16;
  if (padCt > 0) poly.update(Uint8List(padCt), 0, padCt);
  // le64(aadLen=0) || le64(ctLen)
  final lenBlock = Uint8List(16);
  ByteData.view(lenBlock.buffer)
    ..setUint32(0, 0, Endian.little)
    ..setUint32(4, 0, Endian.little)
    ..setUint32(8, ct.length & 0xffffffff, Endian.little)
    ..setUint32(12, (ct.length >> 32) & 0xffffffff, Endian.little);
  poly.update(lenBlock, 0, 16);
  final out = Uint8List(16);
  poly.doFinal(out, 0);
  return out;
}

bool _constTimeEq(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

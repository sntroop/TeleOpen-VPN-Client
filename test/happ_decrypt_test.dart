// test/happ_decrypt_test.dart
//
// Тесты для logic/happ_decrypt.dart.
//
// Чистые перестановки и разбор crypt5-структуры проверяются БЕЗ ключей.
// End-to-end расшифровка crypt5 требует assets/happ/crypt5_final_keys.json
// (34 ключа, извлечённых из Happ APK) — этот тест помечен skip, пока ключей нет.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_vpn/logic/happ_decrypt.dart';

// Реальная crypt5-ссылка пользователя (маркер должен распарситься в qahftrxc).
const _realCrypt5 =
    'happ://crypt5/hfqaz5TTnlQiSxNx2w17kQqWR7LFJdxSGYKYjp2DWSx3BEOIPXTqTLCKPlxAAUHwdiS2rsbWzBAW4Ao4/qyI8g3CRlXn+udIn0xTf2gcGUjja1ivgtmit+ETrKQC/fFvPwnKVUQlK3M5XT09oS3+ys1suEdulnumNN39s/02Lcs+vyT+JwXvZm8CqHjFE=sBU3aFy2eg1g7wCqLTDw/48UoGEnDPPOakW/xZvZz3rxtJ4z+CHCY9s75X9cUIMh4FGooemX3FOLqt3E77Nd7VtTnssIq9jha32tx3lDgwfBwdyJzF0Fu593h0bNb1D+otGMMl2dbOkkcb16hCBFi5hV3+beJek7byGcASgS+BE6iu8X3w/XwXQic1F98TJvPMaQ1WBMQmdaX04hEsRqffygYYUqWc/9ZHI4VNQVL6mSmm9aNJzOxQd7/GyQS2O56GwRif/MAFEvvdK29SGhRUtxKvZVe34M8RWyHYdk4ITEaKAFkhmqlSF1pOJFs/jNqwTmTAPYxnUoloLnt/U1YMKUfTd3A6RdNWEH73qnRGS4GZNcuujalwXJqXU10fGQyob1mX1ukZhG8UlXtWrsB9jUtsf/YzIEczRqXLaEn5v2tXO7HNMCgQwBE0qgu8Alne2eCLFdfgg9CUetgegxW4WKoLDvilv4Jzog2AA/oaN/dE524dXYFdCBwZIVcgGv9ZQTTDNT+KtaJF/C+xV3id0nSNzHB1rAJQF9qhNv9AwzV8hUbt6LpxMaorZgD+Rz+jlTI0UWs5obbztI9+n21XWAqUWgt6j525L3D8y1FzFT5YjLRjxDCSFurC3eihOUXi7Cbdtqtt1DVKe2SrqkaJlQO6vRljMqgyg28YBoqGU=/Xxctr';

void main() {
  group('перестановки обратимы (контракт с amur)', () {
    const sample = 'abcdefghijklmnopqrstuvwxyz0123456789';
    test('inverseM4831f ∘ m4831f == id', () {
      expect(inverseM4831f(m4831f(sample)), sample);
    });
    test('m4842j ∘ m4842j == id', () {
      expect(m4842j(m4842j(sample)), sample);
    });
    test('permute4 ∘ permute4 == id', () {
      expect(permute4(permute4(sample)), sample);
    });
  });

  group('разбор реальной crypt5-ссылки (без ключей)', () {
    test('isHappLink распознаёт', () {
      expect(isHappLink(_realCrypt5), isTrue);
      expect(isHappLink('vless://x@h:443'), isFalse);
    });

    test('маркер извлекается как qahftrxc', () {
      final info = inspect(_realCrypt5);
      expect(info.name, 'crypt5');
      expect(info.mode, 4);
      expect(info.payloadLen, 880);
      expect(info.crypt5Marker, 'qahftrxc');
    });

    test('без ключа -> HappMissingKeyException с маркером', () {
      expect(
        () => decryptHappLink(_realCrypt5, const HappKeys()),
        throwsA(isA<HappMissingKeyException>()
            .having((e) => e.marker, 'marker', 'qahftrxc')),
      );
    });
  });

  group('HappKeys.fromJson', () {
    test('парсит оба формата', () {
      final k = HappKeys.fromJson(
        nativeJson: '{"keys":["AAAA","BBBB"]}',
        crypt5Json: '{"keys":{"qahftrxc":"Q0NDQw=="}}',
      );
      expect(k.nativeKeys, ['AAAA', 'BBBB']);
      expect(k.crypt5Keys['qahftrxc'], 'Q0NDQw==');
      expect(k.isEmpty, isFalse);
    });
  });

  group('end-to-end (нужен assets/happ/crypt5_keys.json от build_happ_assets.py)', () {
    final keyFile = File('assets/happ/crypt5_keys.json');
    final hasKeys = keyFile.existsSync();

    test('crypt5 расшифровывается в ожидаемый URL подписки', () {
      final keys = HappKeys.fromJson(crypt5Json: keyFile.readAsStringSync());
      final out = decryptHappLink(_realCrypt5, keys);
      expect(
        out,
        'https://raw.githubusercontent.com/theavel/free-vless-proxy/refs/heads/main/all.txt',
      );
    }, skip: hasKeys ? false : 'нет assets/happ/crypt5_keys.json');
  });
}

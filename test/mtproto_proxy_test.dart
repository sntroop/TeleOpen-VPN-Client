// Юнит-тесты модели MTProto-прокси (lib/models/mtproto_proxy.dart).
//
// tryParse/isValid/buildLink — это парсинг пользовательского ввода (ссылки из
// чатов) и сборка deep-link для Telegram. Проверяем основные форматы, базовую
// валидацию secret и round-trip ссылки.

import 'package:flutter_test/flutter_test.dart';

import 'package:my_vpn/models/mtproto_proxy.dart';

// 32 hex-символа — валидный простой MTProto secret.
const _hexSecret = '0123456789abcdef0123456789abcdef';

void main() {
  group('isValid', () {
    test('mtproto с hex-secret валиден', () {
      final p = MtProtoProxy.mtproto(server: '1.2.3.4', port: 443, secret: _hexSecret);
      expect(p.isValid, isTrue);
    });

    test('пустой secret невалиден', () {
      final p = MtProtoProxy.mtproto(server: '1.2.3.4', port: 443, secret: '');
      expect(p.isValid, isFalse);
    });

    test('некорректный порт невалиден', () {
      final p = MtProtoProxy.mtproto(server: '1.2.3.4', port: 0, secret: _hexSecret);
      expect(p.isValid, isFalse);
      final p2 = MtProtoProxy.mtproto(server: '1.2.3.4', port: 70000, secret: _hexSecret);
      expect(p2.isValid, isFalse);
    });
  });

  group('tryParse', () {
    test('tg://proxy с server/port/secret', () {
      final p = MtProtoProxy.tryParse(
          'tg://proxy?server=proxy.example.com&port=443&secret=$_hexSecret');
      expect(p, isNotNull);
      expect(p!.kind, TelegramProxyKind.mtproto);
      expect(p.server, 'proxy.example.com');
      expect(p.port, 443);
      expect(p.secret, _hexSecret);
    });

    test('https://t.me/proxy эквивалентен tg://proxy', () {
      final p = MtProtoProxy.tryParse(
          'https://t.me/proxy?server=1.2.3.4&port=8443&secret=$_hexSecret');
      expect(p, isNotNull);
      expect(p!.server, '1.2.3.4');
      expect(p.port, 8443);
    });

    test('голый формат host:port:secret', () {
      final p = MtProtoProxy.tryParse('5.6.7.8:443:$_hexSecret');
      expect(p, isNotNull);
      expect(p!.server, '5.6.7.8');
      expect(p.port, 443);
    });

    test('мусор → null', () {
      expect(MtProtoProxy.tryParse(''), isNull);
      expect(MtProtoProxy.tryParse('просто текст'), isNull);
      expect(MtProtoProxy.tryParse('http://example.com/page'), isNull);
    });
  });

  group('buildLink', () {
    test('round-trip: build → tryParse даёт те же server/port/secret', () {
      final original =
          MtProtoProxy.mtproto(server: 'rt.example.com', port: 443, secret: _hexSecret);
      final link = original.buildLink(https: true);
      final parsed = MtProtoProxy.tryParse(link);
      expect(parsed, isNotNull);
      expect(parsed!.server, original.server);
      expect(parsed.port, original.port);
      expect(parsed.secret, original.secret);
    });

    test('невалидный прокси → buildLink бросает исключение', () {
      final bad = MtProtoProxy.mtproto(server: '', port: 443, secret: _hexSecret);
      expect(() => bad.buildLink(), throwsA(isA<MtProtoProxyException>()));
    });
  });

  group('displayName', () {
    test('явное имя приоритетнее server:port', () {
      final p = MtProtoProxy.mtproto(
          server: '1.2.3.4', port: 443, secret: _hexSecret, name: 'Мой прокси');
      expect(p.displayName, 'Мой прокси');
    });
    test('без имени → server:port', () {
      final p = MtProtoProxy.mtproto(server: '1.2.3.4', port: 443, secret: _hexSecret);
      expect(p.displayName, '1.2.3.4:443');
    });
  });
}

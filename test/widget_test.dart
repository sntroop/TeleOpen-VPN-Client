// Юнит-тесты разбора URI (lib/logic/parsers.dart).
//
// parseUri — самое security-критичное место клиента: через него проходят
// все пользовательские/подписочные ссылки на серверы. Этот файл проверяет,
// что валидные ссылки парсятся в нужный протокол с верными host/port, а
// мусор аккуратно возвращает null (а не кидает исключение и не падает).

import 'package:flutter_test/flutter_test.dart';

import 'package:my_vpn/logic/parsers.dart';
import 'package:my_vpn/models/vpn_node.dart';

void main() {
  group('parseUri — валидные ссылки', () {
    test('vless reality парсится в host/port/protocol', () {
      const uri =
          'vless://11111111-2222-3333-4444-555555555555@example.com:443'
          '?security=reality&pbk=abc&type=tcp&flow=xtls-rprx-vision#MyNode';
      final node = parseUri(uri);
      expect(node, isNotNull);
      expect(node!.protocol, VpnProtocol.vless);
      expect(node.address, 'example.com');
      expect(node.port, 443);
    });

    test('trojan + tls', () {
      final node = parseUri('trojan://pass@1.2.3.4:8443?sni=a.com#T');
      expect(node, isNotNull);
      expect(node!.protocol, VpnProtocol.trojan);
      expect(node.address, '1.2.3.4');
      expect(node.port, 8443);
    });

    test('hysteria2', () {
      final node = parseUri('hysteria2://pw@h.example.org:36712?sni=h#HY');
      expect(node, isNotNull);
      expect(node!.protocol, VpnProtocol.hysteria2);
      expect(node.port, 36712);
    });
  });

  group('parseUri — мусор не роняет приложение', () {
    test('пустая строка → null', () {
      expect(parseUri(''), isNull);
      expect(parseUri('   '), isNull);
    });

    test('неизвестная схема → null', () {
      expect(parseUri('ftp://whatever'), isNull);
      expect(parseUri('просто текст'), isNull);
    });

    test('обрезанный vless без host → null, без исключения', () {
      expect(parseUri('vless://'), isNull);
    });
  });
}

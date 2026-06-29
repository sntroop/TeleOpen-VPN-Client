// Юнит-тесты разбора URI (lib/logic/parsers.dart) — расширенный набор.
//
// parseUri — самое security-критичное место клиента: через него проходят все
// пользовательские/подписочные ссылки. Здесь проверяем форматы, которых не
// было в widget_test.dart: vmess(base64 JSON), shadowsocks(base64 userinfo),
// socks, HTML-escaped ссылки и устойчивость к мусору.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:my_vpn/logic/parsers.dart';
import 'package:my_vpn/models/vpn_node.dart';

void main() {
  group('parseUri — vmess (base64 JSON, v2rayN)', () {
    test('распарсивает add/port/id из base64-тела', () {
      final payload = base64.encode(utf8.encode(jsonEncode({
        'v': '2',
        'ps': 'My VMess',
        'add': 'vmess.example.com',
        'port': '443',
        'id': '11111111-2222-3333-4444-555555555555',
        'net': 'ws',
      })));
      final node = parseUri('vmess://$payload');
      expect(node, isNotNull);
      expect(node!.protocol, VpnProtocol.vmess);
      expect(node.address, 'vmess.example.com');
      expect(node.port, 443);
      expect(node.name, 'My VMess');
      expect(node.params['uuid'], '11111111-2222-3333-4444-555555555555');
    });

    test('vmess с пустым add/id → null (не падает)', () {
      final payload = base64.encode(utf8.encode(jsonEncode({
        'add': '',
        'port': '443',
        'id': '',
      })));
      expect(parseUri('vmess://$payload'), isNull);
    });
  });

  group('parseUri — shadowsocks', () {
    test('SIP002 с base64 userinfo', () {
      final ui = base64.encode(utf8.encode('aes-256-gcm:secretpass'));
      final node = parseUri('ss://$ui@1.2.3.4:8388#SS-Node');
      expect(node, isNotNull);
      expect(node!.protocol, VpnProtocol.shadowsocks);
      expect(node.address, '1.2.3.4');
      expect(node.port, 8388);
      expect(node.name, 'SS-Node');
      expect(node.params['method'], 'aes-256-gcm');
    });

    test('legacy полностью base64 (method:pass@host:port)', () {
      final body = base64.encode(utf8.encode('aes-256-gcm:pw@5.6.7.8:9999'));
      final node = parseUri('ss://$body#Legacy');
      expect(node, isNotNull);
      expect(node!.address, '5.6.7.8');
      expect(node.port, 9999);
    });
  });

  group('parseUri — socks', () {
    test('socks://host:port без креденшелов', () {
      final node = parseUri('socks://1.2.3.4:1080#Sock');
      expect(node, isNotNull);
      expect(node!.protocol, VpnProtocol.socks);
      expect(node.address, '1.2.3.4');
      expect(node.port, 1080);
    });

    test('socks без порта → дефолт 1080', () {
      final node = parseUri('socks://example.org#S');
      expect(node, isNotNull);
      expect(node!.port, 1080);
    });
  });

  group('parseUri — HTML-escaped ссылки', () {
    test('&amp; в query не ломает разбор vless', () {
      const uri =
          'vless://11111111-2222-3333-4444-555555555555@example.com:443'
          '?security=reality&amp;pbk=abc&amp;type=tcp#Esc';
      final node = parseUri(uri);
      expect(node, isNotNull);
      expect(node!.protocol, VpnProtocol.vless);
      expect(node.address, 'example.com');
      expect(node.port, 443);
    });
  });

  group('parseUri — устойчивость к мусору', () {
    test('обрезанный vmess без base64 → null', () {
      expect(parseUri('vmess://'), isNull);
    });
    test('ss с мусором вместо base64 → null', () {
      expect(parseUri('ss://@@@:::'), isNull);
    });
    test('случайный текст со схожим префиксом → null', () {
      expect(parseUri('vmessssss'), isNull);
    });
  });
}

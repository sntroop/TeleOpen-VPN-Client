// lib/logic/subscriptions.dart
//
// Загрузка подписок с Happ-заголовками + fallback UA + CisVPN JSON-формат.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/vpn_node.dart';
import 'parsers.dart';

class SubscriptionLoadResult {
  final List<VpnNode> nodes;
  final String? error;
  final String groupTitle;
  final Map<String, int> userInfo;
  final int rawBytes;
  final String? announce;

  SubscriptionLoadResult({
    required this.nodes,
    this.error,
    this.groupTitle = '',
    this.userInfo = const {},
    this.rawBytes = 0,
    this.announce,
  });
}

class SubscriptionLoader {
  // Happ-заголовки (мимикрия под мобильный клиент Happ)
  static const _happHeaders = {
    'user-agent': 'Happ/3.20.4/Android/17782185961531805698',
    'x-device-locale': 'ru',
    'x-hwid': '116383e366cf0719',
    'x-device-os': 'Android',
    'x-ver-os': '16',
    'x-device-model': 'SM-A366E',
    'accept-encoding': 'gzip',
  };

  static const _fallbackUserAgents = [
    'V2RayTun/1.0',
    'hiddify/2.0.5',
    'v2rayNG/1.8.36',
    'sing-box/1.9.0',
    'clash-meta/1.18.0',
  ];

  static Future<SubscriptionLoadResult> load(String url) async {
    final trimmed = url.trim();

    // HIGH-1: подписка фетчится по URL, который ввёл пользователь/получен из
    // маркета — без проверки это SSRF (можно заставить приложение ходить на
    // 127.0.0.1, метадату облака 169.254.169.254, внутреннюю сеть). Разрешаем
    // только http/https на публичные адреса; внутренние диапазоны режем.
    final guard = await _validateSubUrl(trimmed);
    if (guard != null) {
      return SubscriptionLoadResult(nodes: [], error: guard);
    }

    http.Response? res;
    String? lastError;

    // 1) Сначала Happ
    try {
      final r = await http.get(Uri.parse(trimmed), headers: _happHeaders)
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200 && _isValidBody(r.body)) {
        res = r;
      }
    } on TimeoutException {
      lastError = 'Happ: таймаут';
    } catch (e) {
      lastError = 'Happ: $e';
    }

    // 2) Fallback UAs
    if (res == null) {
      for (final ua in _fallbackUserAgents) {
        try {
          final r = await http.get(Uri.parse(trimmed), headers: {
            'User-Agent': ua,
            'Accept-Encoding': 'gzip',
            'Accept': '*/*',
          }).timeout(const Duration(seconds: 15));
          if (r.statusCode == 200 && _isValidBody(r.body)) {
            res = r;
            break;
          }
          lastError = '$ua → HTTP ${r.statusCode}';
        } on TimeoutException {
          lastError = '$ua: таймаут';
        } catch (e) {
          lastError = '$ua: $e';
        }
      }
    }

    if (res == null) {
      return SubscriptionLoadResult(
        nodes: [],
        error: lastError ?? 'Сервер отклонил все клиенты или подписка пуста',
      );
    }

    String decoded;
    try {
      decoded = utf8.decode(
          base64.decode(res.body.trim().replaceAll(RegExp(r'\s+'), '')));
    } catch (_) {
      // Тело не в base64 — это штатно: многие подписки отдают plaintext-список
      // ссылок. Используем тело как есть, без логирования (не ошибка).
      decoded = res.body;
    }

    // Парсим #-метаданные из тела (формат Happ/sing-box/clash с inline-комментариями)
    final bodyMeta = _parseBodyMeta(decoded);

    // HTTP-заголовки имеют приоритет, если заполнены; иначе берём из тела
    final httpTitle = _decodeHeader(res.headers['profile-title'] ?? '');
    final groupTitle = httpTitle.isNotEmpty
        ? httpTitle
        : _decodeHeader(bodyMeta['profile-title'] ?? '');
    final userInfo = (res.headers['subscription-userinfo']?.isNotEmpty == true)
        ? _parseUserInfo(res.headers['subscription-userinfo'])
        : _parseUserInfo(bodyMeta['subscription-userinfo']);
    final announceRaw = (res.headers['announce']?.isNotEmpty == true)
        ? res.headers['announce']!
        : (bodyMeta['announce'] ?? '');
    final announce = _decodeHeader(announceRaw);

    final nodes = <VpnNode>[];
    final lines =
        decoded.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.startsWith('vless://') ||
          lower.startsWith('vmess://') ||
          lower.startsWith('ssr://') ||
          lower.startsWith('ss://') ||
          lower.startsWith('trojan://') ||
          lower.startsWith('hysteria://') ||
          lower.startsWith('hysteria2://') ||
          lower.startsWith('hy2://') ||
          lower.startsWith('tuic://') ||
          lower.startsWith('socks://')) {
        final node = parseUri(line);
        if (node != null) nodes.add(node);
      }
    }

    if (nodes.isEmpty) {
      nodes.addAll(_parseJsonConfig(decoded));
    }

    if (nodes.isEmpty) {
      return SubscriptionLoadResult(
        nodes: [],
        error: 'Не удалось распарсить серверы из подписки',
        groupTitle: groupTitle,
        userInfo: userInfo,
        announce: announce.isNotEmpty ? announce : null,
      );
    }

    return SubscriptionLoadResult(
      nodes: nodes,
      groupTitle: groupTitle,
      userInfo: userInfo,
      rawBytes: res.bodyBytes.length,
      announce: announce.isNotEmpty ? announce : null,
    );
  }

  /// Возвращает текст ошибки, если URL небезопасен для фетча (SSRF), иначе null.
  static Future<String?> _validateSubUrl(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'Некорректный URL подписки';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Поддерживаются только http/https подписки';
    }
    // Резолвим хост и проверяем КАЖДЫЙ адрес: достаточно одного внутреннего,
    // чтобы отклонить (защита от DNS-rebinding в т.ч.).
    List<InternetAddress> addrs;
    try {
      // Если host — уже IP-литерал, lookup вернёт его же.
      addrs = await InternetAddress.lookup(uri.host)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      return 'Не удалось проверить адрес подписки';
    }
    if (addrs.isEmpty) return 'Адрес подписки не резолвится';
    for (final a in addrs) {
      if (_isPrivateAddress(a)) {
        return 'Адрес подписки указывает на внутреннюю сеть — отклонено';
      }
    }
    return null;
  }

  /// true для loopback/private/link-local/multicast/CGNAT и cloud-metadata.
  static bool _isPrivateAddress(InternetAddress a) {
    if (a.isLoopback || a.isLinkLocal || a.isMulticast) return true;
    final raw = a.rawAddress;
    if (a.type == InternetAddressType.IPv4 && raw.length == 4) {
      final b0 = raw[0], b1 = raw[1];
      if (b0 == 10) return true;                       // 10.0.0.0/8
      if (b0 == 127) return true;                      // 127.0.0.0/8
      if (b0 == 0) return true;                        // 0.0.0.0/8
      if (b0 == 169 && b1 == 254) return true;         // link-local / metadata
      if (b0 == 172 && b1 >= 16 && b1 <= 31) return true; // 172.16/12
      if (b0 == 192 && b1 == 168) return true;         // 192.168/16
      if (b0 == 100 && b1 >= 64 && b1 <= 127) return true; // 100.64/10 CGNAT
      return false;
    }
    if (a.type == InternetAddressType.IPv6 && raw.length == 16) {
      if (raw[0] == 0xfe && (raw[1] & 0xc0) == 0x80) return true; // fe80::/10
      if ((raw[0] & 0xfe) == 0xfc) return true;        // fc00::/7 ULA
      // IPv4-mapped ::ffff:a.b.c.d → проверяем встроенный v4
      final isV4Mapped = raw.take(10).every((x) => x == 0) &&
          raw[10] == 0xff && raw[11] == 0xff;
      if (isV4Mapped) {
        return _isPrivateAddress(InternetAddress.fromRawAddress(raw.sublist(12)));
      }
      return false;
    }
    return false;
  }

  static bool _isValidBody(String body) {
    final t = body.trim();
    if (t.isEmpty) return false;
    if (t.contains('0.0.0.0') && t.length < 200) return false;

    if (t.contains('vless://') ||
        t.contains('vmess://') ||
        t.contains('trojan://') ||
        t.contains('ss://') ||
        t.contains('hysteria') ||
        t.contains('hy2://') ||
        t.contains('tuic://')) {
      return true;
    }

    if (t.startsWith('[') || t.startsWith('{')) {
      try {
        final j = jsonDecode(t);
        final List configs = j is List ? j : [j];
        return configs.any((c) =>
            c is Map &&
            (c['outbounds'] as List?)
                    ?.any((o) => o is Map && o['protocol'] != null) == true);
      } catch (_) {
        return t.length > 100;
      }
    }

    try {
      final dec = utf8.decode(base64.decode(t.replaceAll(RegExp(r'\s+'), '')));
      return dec.contains('vless://') ||
          dec.contains('vmess://') ||
          dec.contains('trojan://') ||
          dec.contains('ss://');
    } catch (_) {}

    return false;
  }

  static String _decodeHeader(String? val) {
    if (val == null) return '';
    if (val.startsWith('base64:')) {
      try {
        return utf8.decode(base64.decode(val.substring(7)));
      } catch (_) {
        // Заголовок помечен base64:, но не декодируется — отдаём как есть
        // (штатный fallback для кривых заголовков), не ошибка.
        return val;
      }
    }
    return val;
  }

  static Map<String, int> _parseUserInfo(String? info) {
    if (info == null) return {};
    final map = <String, int>{};
    for (final e in info.split(';')) {
      final kv = e.split('=');
      if (kv.length == 2) map[kv[0].trim()] = int.tryParse(kv[1].trim()) ?? 0;
    }
    return map;
  }

  static List<VpnNode> _parseJsonConfig(String body) {
    final nodes = <VpnNode>[];
    try {
      final j = jsonDecode(body);
      final List configs = j is List ? j : [j];
      for (final cfg in configs) {
        if (cfg is! Map) continue;
        final remark = (cfg['remarks'] ?? cfg['remark'] ?? 'CisVPN').toString();
        final outbounds = cfg['outbounds'];
        if (outbounds is! List) continue;
        Map? vlessOut;
        for (final o in outbounds) {
          if (o is Map && o['protocol'] == 'vless') {
            vlessOut = o;
            break;
          }
        }
        if (vlessOut == null) continue;
        try {
          final vnext = (vlessOut['settings']['vnext'] as List)[0] as Map;
          final stream = vlessOut['streamSettings'] as Map;
          final reality = (stream['realitySettings'] as Map?) ?? {};
          final userId = vnext['users'][0]['id'].toString();
          final address = vnext['address'].toString();
          final port = vnext['port'];
          final flow = vnext['users'][0]['flow']?.toString() ?? '';
          final security = stream['security']?.toString() ?? 'none';
          final network = stream['network']?.toString() ?? 'tcp';
          final sni = reality['serverName']?.toString() ?? '';
          final fp = reality['fingerprint']?.toString() ?? 'chrome';
          final pbk = reality['publicKey']?.toString() ?? '';
          final sid = reality['shortId']?.toString() ?? '';
          // HIGH-2: значения берутся из недоверенного JSON. Собираем URI через
          // Uri(...) — он сам percent-кодирует userInfo/query/fragment, поэтому
          // символы `&`, `#`, пробелы и т.п. не могут «вырваться» и подменить
          // другие параметры (инъекция в строку конфига).
          final portNum = port is int ? port : int.tryParse('$port');
          final uri = Uri(
            scheme: 'vless',
            userInfo: userId,
            host: address,
            port: portNum,
            queryParameters: {
              'security': security,
              'sni': sni,
              'fp': fp,
              'pbk': pbk,
              'sid': sid,
              'type': network,
              'flow': flow,
            },
            fragment: remark,
          ).toString();
          final node = parseUri(uri);
          if (node != null) nodes.add(node);
        } catch (_) {}
      }
    } catch (_) {}
    return nodes;
  }

  /// Извлекает метаданные из #-комментариев в теле подписки.
  /// Формат: "#ключ: значение" — используется в Happ/sing-box/clash-стиле.
  static Map<String, String> _parseBodyMeta(String body) {
    final meta = <String, String>{};
    for (final line in body.split('\n')) {
      final t = line.trim();
      if (!t.startsWith('#')) continue;
      final colonIdx = t.indexOf(':');
      if (colonIdx < 2) continue;
      final key = t.substring(1, colonIdx).trim().toLowerCase();
      final value = t.substring(colonIdx + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        meta[key] = value;
      }
    }
    return meta;
  }
}

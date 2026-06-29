// lib/models/mtproto_proxy.dart
//
// Модель MTProto Proxy для Telegram.
//
// MTProto Proxy — это НЕ VPN-протокол вроде VLESS/Trojan. Его не поднимает
// xray-движок приложения. Это прокси, который *устанавливается внутрь
// Telegram*: при открытии deep-link `tg://proxy?...` Telegram сам показывает
// штатное окно «Подключить прокси». Задача клиента — собрать корректную
// ссылку и отдать её в Telegram (или его форк) через системный Intent.
//
// Поддерживаемые форматы импорта:
//   tg://proxy?server=HOST&port=PORT&secret=SECRET
//   tg://socks?server=HOST&port=PORT&user=USER&pass=PASS
//   https://t.me/proxy?server=HOST&port=PORT&secret=SECRET
//   https://t.me/socks?server=HOST&port=PORT&user=USER&pass=PASS
//
// Виды secret для MTProto:
//   - простой       — 32 hex-символа (16 байт)
//   - dd-secret     — префикс "dd" + 32 hex (random padding, устаревший)
//   - fake-TLS      — префикс "ee" + 32 hex + домен в hex, ИЛИ
//                     base64url той же структуры (начинается на байт 0xEE)
// Telegram понимает все три; мы их не валидируем по содержимому, только
// проверяем что secret непустой и состоит из допустимых символов.

import 'dart:convert';

import '../logic/crash_log.dart';

class MtProtoProxyException implements Exception {
  final String message;
  MtProtoProxyException(this.message);
  @override
  String toString() => 'MtProtoProxyException: $message';
}

/// Тип прокси Telegram.
enum TelegramProxyKind {
  /// MTProto Proxy — использует secret.
  mtproto,

  /// SOCKS5 Proxy — использует user/pass (опционально).
  socks5,
}

extension TelegramProxyKindX on TelegramProxyKind {
  /// Путь deep-link: tg://<path> и https://t.me/<path>
  String get linkPath => switch (this) {
        TelegramProxyKind.mtproto => 'proxy',
        TelegramProxyKind.socks5 => 'socks',
      };

  String get label => switch (this) {
        TelegramProxyKind.mtproto => 'MTProto Proxy',
        TelegramProxyKind.socks5 => 'SOCKS5 Proxy',
      };
}

/// Описание одного Telegram-прокси.
class MtProtoProxy {
  final TelegramProxyKind kind;
  final String server;
  final int port;

  /// Для MTProto — secret (hex или base64url). Для SOCKS — пусто.
  final String secret;

  /// Для SOCKS — логин/пароль. Для MTProto — пусто.
  final String user;
  final String pass;

  /// Необязательное имя для отображения в UI.
  final String name;

  /// Добавлен ли прокси в избранное. Сериализуется (как isFavorite у VpnNode).
  bool isFavorite;

  /// Рантайм-пинг в мс (TCP-коннект до server:port). Не сериализуется —
  /// как и pingMs у VpnNode, это метрика текущей сессии.
  int? pingMs;

  MtProtoProxy({
    required this.kind,
    required this.server,
    required this.port,
    this.secret = '',
    this.user = '',
    this.pass = '',
    this.name = '',
    this.isFavorite = false,
    this.pingMs,
  });

  /// MTProto-конструктор (наиболее частый сценарий).
  factory MtProtoProxy.mtproto({
    required String server,
    required int port,
    required String secret,
    String name = '',
    bool isFavorite = false,
  }) =>
      MtProtoProxy(
        kind: TelegramProxyKind.mtproto,
        server: server,
        port: port,
        secret: secret,
        name: name,
        isFavorite: isFavorite,
      );

  /// SOCKS5-конструктор.
  factory MtProtoProxy.socks5({
    required String server,
    required int port,
    String user = '',
    String pass = '',
    String name = '',
    bool isFavorite = false,
  }) =>
      MtProtoProxy(
        kind: TelegramProxyKind.socks5,
        server: server,
        port: port,
        user: user,
        pass: pass,
        name: name,
        isFavorite: isFavorite,
      );

  /// Имя для UI: явное имя → иначе server:port.
  String get displayName => name.isNotEmpty ? name : '$server:$port';

  /// true, если прокси прошёл базовую валидацию.
  bool get isValid {
    if (server.trim().isEmpty) return false;
    if (port <= 0 || port > 65535) return false;
    if (kind == TelegramProxyKind.mtproto) {
      return _isValidSecret(secret);
    }
    return true; // у SOCKS auth опционально
  }

  /// Собирает deep-link для Telegram.
  ///
  /// [https] = false → `tg://proxy?...` (открывается напрямую в Telegram)
  /// [https] = true  → `https://t.me/proxy?...` (откроется через t.me,
  ///                    полезно для шеринга в текстовом виде)
  String buildLink({bool https = false}) {
    if (!isValid) {
      throw MtProtoProxyException('Некорректные параметры прокси');
    }

    final params = <String, String>{
      'server': server.trim(),
      'port': port.toString(),
    };

    if (kind == TelegramProxyKind.mtproto) {
      params['secret'] = secret.trim();
    } else {
      if (user.isNotEmpty) params['user'] = user;
      if (pass.isNotEmpty) params['pass'] = pass;
    }

    // Uri сам корректно процентно-кодирует значения (secret c доменом
    // fake-TLS, пароли со спецсимволами и т.п.).
    if (https) {
      return Uri(
        scheme: 'https',
        host: 't.me',
        path: '/${kind.linkPath}',
        queryParameters: params,
      ).toString();
    }

    // Для tg:// собираем строку вручную: Dart-овский Uri для нестандартных
    // схем по-разному ведёт себя с host/path в разных версиях SDK. Ручная
    // сборка query-строки надёжнее. encodeComponent (а не encodeQueryComponent)
    // — чтобы пробел кодировался как %20, а не как «+»: Telegram ждёт %20.
    final query = params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return 'tg://${kind.linkPath}?$query';
  }

  /// Разбирает строку: deep-link (`tg://`, `https://t.me/`) либо
  /// «голый» `server:port:secret`. Возвращает null если не распознано.
  static MtProtoProxy? tryParse(String input, {String name = ''}) {
    final raw = input.trim();
    if (raw.isEmpty) return null;

    // 1) Полноценный deep-link.
    final lower = raw.toLowerCase();
    if (lower.startsWith('tg://') ||
        lower.startsWith('https://t.me/') ||
        lower.startsWith('http://t.me/') ||
        lower.startsWith('t.me/')) {
      return _parseLink(raw, name: name);
    }

    // 2) «Голый» формат host:port:secret (часто так шарят в чатах).
    final parts = raw.split(':');
    if (parts.length == 3) {
      final port = int.tryParse(parts[1].trim());
      if (port != null) {
        final p = MtProtoProxy.mtproto(
          server: parts[0].trim(),
          port: port,
          secret: parts[2].trim(),
          name: name,
        );
        return p.isValid ? p : null;
      }
    }

    return null;
  }

  static MtProtoProxy? _parseLink(String raw, {String name = ''}) {
    // Нормализуем «t.me/...» без схемы.
    var s = raw;
    if (s.toLowerCase().startsWith('t.me/')) s = 'https://$s';

    final uri = Uri.tryParse(s);
    if (uri == null) return null;

    // Путь прокси: для tg:// он в host ("proxy"/"socks"),
    // для t.me — в pathSegments.
    String path;
    if (uri.scheme == 'tg') {
      path = uri.host.toLowerCase();
    } else {
      path = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.first.toLowerCase()
          : '';
    }

    final kind = switch (path) {
      'proxy' => TelegramProxyKind.mtproto,
      'socks' => TelegramProxyKind.socks5,
      _ => null,
    };
    if (kind == null) return null;

    final q = uri.queryParameters;
    final server = (q['server'] ?? '').trim();
    final port = int.tryParse((q['port'] ?? '').trim()) ?? 0;
    if (server.isEmpty || port == 0) return null;

    final MtProtoProxy proxy;
    if (kind == TelegramProxyKind.mtproto) {
      proxy = MtProtoProxy.mtproto(
        server: server,
        port: port,
        secret: (q['secret'] ?? '').trim(),
        name: name,
      );
    } else {
      proxy = MtProtoProxy.socks5(
        server: server,
        port: port,
        user: q['user'] ?? '',
        pass: q['pass'] ?? '',
        name: name,
      );
    }
    return proxy.isValid ? proxy : null;
  }

  /// Проверка secret: hex (любой длины, чётной, >= 16 hex), либо base64url.
  /// Намеренно мягкая — Telegram сам отбракует совсем мусор, а нам важнее
  /// не отвергнуть валидный fake-TLS secret с нестандартной длиной.
  static bool _isValidSecret(String secret) {
    final s = secret.trim();
    if (s.length < 16) return false;
    final hex = RegExp(r'^[0-9a-fA-F]+$');
    if (hex.hasMatch(s) && s.length.isEven) return true;
    // base64url (fake-TLS secret иногда шарят так)
    final b64 = RegExp(r'^[A-Za-z0-9_\-=]+$');
    return b64.hasMatch(s);
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'server': server,
        'port': port,
        'secret': secret,
        'user': user,
        'pass': pass,
        'name': name,
        'isFavorite': isFavorite,
      };

  factory MtProtoProxy.fromJson(Map<String, dynamic> j) => MtProtoProxy(
        kind: TelegramProxyKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => TelegramProxyKind.mtproto,
        ),
        server: j['server'] ?? '',
        port: (j['port'] as num?)?.toInt() ?? 0,
        secret: j['secret'] ?? '',
        user: j['user'] ?? '',
        pass: j['pass'] ?? '',
        name: j['name'] ?? '',
        isFavorite: j['isFavorite'] == true,
      );

  MtProtoProxy copyWith({String? name, bool? isFavorite}) => MtProtoProxy(
        kind: kind,
        server: server,
        port: port,
        secret: secret,
        user: user,
        pass: pass,
        name: name ?? this.name,
        isFavorite: isFavorite ?? this.isFavorite,
      );
}

// ════════════════════════════════════════════════════════════════════════════
// ГРУППА MTProto-прокси
//
// Аналог VpnGroup, но для Telegram-прокси. Намеренно отдельная сущность:
// MTProto-прокси и VPN-узлы по-разному «подключаются» (один — в Telegram,
// другой — через xray-движок) и по-разному пингуются, мешать их в одной
// структуре — путаница.
// ════════════════════════════════════════════════════════════════════════════

class MtProtoProxyGroup {
  final String id;
  String title;
  String? subtitle;

  /// Если группа пришла из маркета — id группы на бэкенде (для статистики).
  int? marketGroupId;

  List<MtProtoProxy> proxies;

  /// Свёрнута ли группа в UI (не сериализуется).
  bool isCollapsed;

  MtProtoProxyGroup({
    required this.id,
    required this.title,
    this.subtitle,
    this.marketGroupId,
    required this.proxies,
    this.isCollapsed = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'marketGroupId': marketGroupId,
        'proxies': proxies.map((p) => p.toJson()).toList(),
      };

  static MtProtoProxyGroup fromJson(Map<String, dynamic> j) =>
      MtProtoProxyGroup(
        id: j['id'],
        title: j['title'] ?? '',
        subtitle: j['subtitle'],
        marketGroupId: (j['marketGroupId'] as num?)?.toInt(),
        proxies: ((j['proxies'] as List?) ?? [])
            .map((e) =>
                MtProtoProxy.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );

  /// Сериализация всего списка групп — для shared_preferences.
  static String encode(List<MtProtoProxyGroup> groups) =>
      jsonEncode(groups.map((g) => g.toJson()).toList());

  static List<MtProtoProxyGroup> decode(String s) {
    if (s.isEmpty) return [];
    try {
      final list = jsonDecode(s) as List;
      return list
          .map((e) =>
              MtProtoProxyGroup.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (e, st) {
      // Битый/несовместимый JSON групп прокси в prefs — не роняем приложение,
      // но фиксируем: молчаливая потеря сохранённых прокси иначе незаметна.
      CrashLog.record(e, st, 'mtproto.decode');
      return [];
    }
  }
}

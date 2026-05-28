import 'dart:convert';

class MtProtoProxyException implements Exception {
  final String message;
  MtProtoProxyException(this.message);
  @override
  String toString() => 'MtProtoProxyException: $message';
}

enum TelegramProxyKind {
  
  mtproto,

  
  socks5,
}

extension TelegramProxyKindX on TelegramProxyKind {
  
  String get linkPath => switch (this) {
        TelegramProxyKind.mtproto => 'proxy',
        TelegramProxyKind.socks5 => 'socks',
      };

  String get label => switch (this) {
        TelegramProxyKind.mtproto => 'MTProto Proxy',
        TelegramProxyKind.socks5 => 'SOCKS5 Proxy',
      };
}

class MtProtoProxy {
  final TelegramProxyKind kind;
  final String server;
  final int port;

  
  final String secret;

  
  final String user;
  final String pass;

  
  final String name;

  
  bool isFavorite;

  
  
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

  
  String get displayName => name.isNotEmpty ? name : '$server:$port';

  
  bool get isValid {
    if (server.trim().isEmpty) return false;
    if (port <= 0 || port > 65535) return false;
    if (kind == TelegramProxyKind.mtproto) {
      return _isValidSecret(secret);
    }
    return true; 
  }

  
  
  
  
  
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

    
    
    if (https) {
      return Uri(
        scheme: 'https',
        host: 't.me',
        path: '/${kind.linkPath}',
        queryParameters: params,
      ).toString();
    }

    
    
    
    
    final query = params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return 'tg://${kind.linkPath}?$query';
  }

  
  
  static MtProtoProxy? tryParse(String input, {String name = ''}) {
    final raw = input.trim();
    if (raw.isEmpty) return null;

    
    final lower = raw.toLowerCase();
    if (lower.startsWith('tg://') ||
        lower.startsWith('https://t.me/') ||
        lower.startsWith('http://t.me/') ||
        lower.startsWith('t.me/')) {
      return _parseLink(raw, name: name);
    }

    
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
    
    var s = raw;
    if (s.toLowerCase().startsWith('t.me/')) s = 'https://$s';

    final uri = Uri.tryParse(s);
    if (uri == null) return null;

    
    
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

  
  
  
  static bool _isValidSecret(String secret) {
    final s = secret.trim();
    if (s.length < 16) return false;
    final hex = RegExp(r'^[0-9a-fA-F]+$');
    if (hex.hasMatch(s) && s.length.isEven) return true;
    
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

class MtProtoProxyGroup {
  final String id;
  String title;
  String? subtitle;

  
  int? marketGroupId;

  List<MtProtoProxy> proxies;

  
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
    } catch (_) {
      return [];
    }
  }
}

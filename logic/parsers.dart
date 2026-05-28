import 'dart:convert';

import '../models/vpn_node.dart';

class UriParseException implements Exception {
  final String message;
  UriParseException(this.message);
  @override
  String toString() => 'UriParseException: $message';
}

String _unescapeHtml(String s) {
  return s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&nbsp;', ' ');
}

bool _looksLikeVlessBody(String body) {
  final atIdx = body.indexOf('@');
  if (atIdx < 0) return false;
  final userInfo = body.substring(0, atIdx);

  
  
  
  final decodedUserInfo = Uri.decodeComponent(userInfo);
  final hasColonInUserInfo = decodedUserInfo.contains(':');

  
  final qIdx = body.indexOf('?');
  String q = '';
  if (qIdx >= 0) q = body.substring(qIdx + 1).toLowerCase();

  final hasVlessMarkers = q.contains('security=reality') ||
      q.contains('flow=xtls') ||
      q.contains('pbk=') ||
      q.contains('encryption=none') ||
      q.contains('type=ws') ||
      q.contains('type=grpc') ||
      q.contains('type=tcp') ||
      q.contains('type=httpupgrade') ||
      q.contains('type=xhttp') ||
      q.contains('headertype=');

  return !hasColonInUserInfo && hasVlessMarkers;
}

VpnNode? parseUri(String uri) {
  
  final cleaned = _unescapeHtml(uri).trim();
  if (cleaned.isEmpty) return null;

  try {
    if (cleaned.startsWith('vless://'))      return _parseVless(cleaned);
    if (cleaned.startsWith('vmess://'))      return _parseVmessSmart(cleaned);
    if (cleaned.startsWith('trojan://'))     return _parseTrojan(cleaned);
    if (cleaned.startsWith('hysteria2://') ||
        cleaned.startsWith('hy2://'))        return _parseHysteria2(cleaned);
    if (cleaned.startsWith('ssr://'))        return _parseShadowsocksR(cleaned);
    if (cleaned.startsWith('ss://')) {
      
      final body = cleaned.substring('ss://'.length);
      if (_looksLikeVlessBody(body)) {
        return _parseVless('vless://$body');
      }
      return _parseShadowsocks(cleaned);
    }
    if (cleaned.startsWith('socks://') ||
        cleaned.startsWith('socks5://'))     return _parseSocks(cleaned);
  } catch (e) {
    
    return null;
  }
  return null;
}

VpnNode? _parseVmessSmart(String uri) {
  final body = uri.substring('vmess://'.length).trim();

  
  final hashIdx = body.indexOf('#');
  final payload = hashIdx >= 0 ? body.substring(0, hashIdx) : body;
  if (payload.contains('@')) {
    return _parseVmessSip002(uri);
  }

  
  final decoded = _tryB64Decode(body);
  if (decoded == null) return null;

  final trimmedDecoded = decoded.trim();

  
  if (trimmedDecoded.startsWith('{')) {
    return _parseVmessFromJson(uri, trimmedDecoded);
  }

  
  if (trimmedDecoded.contains('@')) {
    final reconstructed = 'vless://${_unescapeHtml(trimmedDecoded)}';
    return _parseVless(reconstructed);
  }

  return null;
}

VpnNode _parseVless(String uri) {
  final u = Uri.parse(uri);
  final uuid = Uri.decodeComponent(u.userInfo);
  final host = u.host;
  final port = u.port == 0 ? 443 : u.port;
  if (uuid.isEmpty || host.isEmpty) throw UriParseException('VLESS: пустой uuid или host');

  final q = u.queryParameters;
  final name = u.fragment.isNotEmpty ? Uri.decodeComponent(u.fragment) : host;

  return VpnNode(
    id: 'vless_${_id(uri)}',
    name: name,
    address: host,
    port: port,
    protocol: VpnProtocol.vless,
    rawUri: uri,
    params: {
      'uuid': uuid,
      'security': q['security'] ?? 'none',
      'sni': q['sni'] ?? q['peer'] ?? '',
      'fp': q['fp'] ?? 'chrome',
      'pbk': q['pbk'] ?? '',                          
      'sid': q['sid'] ?? '',                          
      'spx': q['spx'] ?? '',                          
      'flow': q['flow'] ?? '',                        
      'type': q['type'] ?? 'tcp',                     
      'host': q['host'] ?? '',                        
      'path': q['path'] ?? '/',                       
      'serviceName': q['serviceName'] ?? '',          
      'headerType': q['headerType'] ?? 'none',        
      'alpn': q['alpn'] ?? '',
      'encryption': q['encryption'] ?? 'none',
    },
  );
}

VpnNode _parseVmessFromJson(String uri, String decoded) {
  final Map<String, dynamic> j;
  try {
    j = jsonDecode(decoded) as Map<String, dynamic>;
  } catch (_) {
    throw UriParseException('VMESS: тело не JSON');
  }

  final host = (j['add'] ?? '').toString();
  final port = int.tryParse((j['port'] ?? 0).toString()) ?? 0;
  final uuid = (j['id'] ?? '').toString();
  if (host.isEmpty || port == 0 || uuid.isEmpty) {
    throw UriParseException('VMESS: пустой add/port/id');
  }
  final name = (j['ps'] ?? host).toString();

  return VpnNode(
    id: 'vmess_${_id(uri)}',
    name: name,
    address: host,
    port: port,
    protocol: VpnProtocol.vmess,
    rawUri: uri,
    params: {
      'uuid': uuid,
      'aid': int.tryParse((j['aid'] ?? 0).toString()) ?? 0,
      'security': (j['scy'] ?? 'auto').toString(),    
      'type': (j['net'] ?? 'tcp').toString(),
      'host': (j['host'] ?? '').toString(),
      'path': (j['path'] ?? '/').toString(),
      'tls': (j['tls'] ?? '').toString(),
      'sni': (j['sni'] ?? '').toString(),
      'fp': (j['fp'] ?? '').toString(),
      'alpn': (j['alpn'] ?? '').toString(),
      'headerType': (j['type'] ?? 'none').toString(),
    },
  );
}

VpnNode _parseVmessSip002(String uri) {
  final u = Uri.parse(uri);
  final uuid = Uri.decodeComponent(u.userInfo);
  final host = u.host;
  final port = u.port == 0 ? 443 : u.port;
  if (uuid.isEmpty || host.isEmpty) {
    throw UriParseException('VMESS: пустой uuid или host');
  }
  final q = u.queryParameters;
  final name = u.fragment.isNotEmpty ? Uri.decodeComponent(u.fragment) : host;
  return VpnNode(
    id: 'vmess_${_id(uri)}',
    name: name,
    address: host,
    port: port,
    protocol: VpnProtocol.vmess,
    rawUri: uri,
    params: {
      'uuid': uuid,
      'aid': int.tryParse(q['aid'] ?? '0') ?? 0,
      'security': q['security'] ?? 'auto',
      'type': q['type'] ?? 'tcp',
      'host': q['host'] ?? '',
      'path': q['path'] ?? '/',
      'tls': q['tls'] ?? (q['security'] == 'tls' ? 'tls' : ''),
      'sni': q['sni'] ?? '',
      'fp': q['fp'] ?? '',
      'alpn': q['alpn'] ?? '',
      'headerType': q['headerType'] ?? 'none',
    },
  );
}

VpnNode _parseTrojan(String uri) {
  final u = Uri.parse(uri);
  final password = Uri.decodeComponent(u.userInfo);
  final host = u.host;
  final port = u.port == 0 ? 443 : u.port;
  if (password.isEmpty || host.isEmpty) throw UriParseException('TROJAN: пустой password или host');
  final q = u.queryParameters;
  final name = u.fragment.isNotEmpty ? Uri.decodeComponent(u.fragment) : host;

  return VpnNode(
    id: 'trojan_${_id(uri)}',
    name: name,
    address: host,
    port: port,
    protocol: VpnProtocol.trojan,
    rawUri: uri,
    params: {
      'password': password,
      'sni': q['sni'] ?? q['peer'] ?? '',
      'fp': q['fp'] ?? 'chrome',
      'type': q['type'] ?? 'tcp',
      'host': q['host'] ?? '',
      'path': q['path'] ?? '/',
      'serviceName': q['serviceName'] ?? '',
      'alpn': q['alpn'] ?? '',
      'allowInsecure': q['allowInsecure'] == '1',
    },
  );
}

VpnNode _parseHysteria2(String uri) {
  final u = Uri.parse(uri);
  final password = Uri.decodeComponent(u.userInfo);
  final host = u.host;
  final port = u.port == 0 ? 443 : u.port;
  if (password.isEmpty || host.isEmpty) throw UriParseException('HYSTERIA2: пустой password или host');
  final q = u.queryParameters;
  final name = u.fragment.isNotEmpty ? Uri.decodeComponent(u.fragment) : host;

  return VpnNode(
    id: 'hy2_${_id(uri)}',
    name: name,
    address: host,
    port: port,
    protocol: VpnProtocol.hysteria2,
    rawUri: uri,
    params: {
      'password': password,
      'sni': q['sni'] ?? '',
      'insecure': q['insecure'] == '1',
      'obfs': q['obfs'] ?? '',
      'obfsPassword': q['obfs-password'] ?? '',
      'alpn': q['alpn'] ?? '',
    },
  );
}

VpnNode _parseShadowsocks(String uri) {
  String body = uri.substring('ss://'.length);

  
  String? fragment;
  final hashIdx = body.indexOf('#');
  if (hashIdx >= 0) {
    fragment = Uri.decodeComponent(body.substring(hashIdx + 1));
    body = body.substring(0, hashIdx);
  }

  
  String? query;
  final qIdx = body.indexOf('?');
  if (qIdx >= 0) {
    query = body.substring(qIdx + 1);
    body = body.substring(0, qIdx);
  }

  String method = '';
  String password = '';
  String host = '';
  int port = 0;

  if (body.contains('@')) {
    
    final atIdx = body.lastIndexOf('@');
    final userInfo = body.substring(0, atIdx);
    final hostPart = body.substring(atIdx + 1);

    
    final decodedUserInfo = _tryB64Decode(userInfo) ?? Uri.decodeComponent(userInfo);
    final colonIdx = decodedUserInfo.indexOf(':');
    if (colonIdx < 0) {
      throw UriParseException('SS: невалидный method:password');
    }
    method = decodedUserInfo.substring(0, colonIdx);
    password = decodedUserInfo.substring(colonIdx + 1);

    final hp = hostPart.split(':');
    if (hp.length < 2) throw UriParseException('SS: невалидный host:port');
    host = hp[0];
    port = int.parse(hp[1]);
  } else {
    
    final decoded = _tryB64Decode(body);
    if (decoded == null) throw UriParseException('SS: не удалось декодировать base64');
    final atIdx = decoded.lastIndexOf('@');
    if (atIdx < 0) throw UriParseException('SS: нет @ в декодированном теле');
    final mp = decoded.substring(0, atIdx);
    final hp = decoded.substring(atIdx + 1);
    final colonInMp = mp.indexOf(':');
    if (colonInMp < 0) throw UriParseException('SS: невалидный method:password');
    method = mp.substring(0, colonInMp);
    password = mp.substring(colonInMp + 1);
    final colonInHp = hp.lastIndexOf(':');
    if (colonInHp < 0) throw UriParseException('SS: невалидный host:port');
    host = hp.substring(0, colonInHp);
    port = int.parse(hp.substring(colonInHp + 1));
  }

  if (method.isEmpty || host.isEmpty || port == 0) {
    throw UriParseException('SS: пустой method/host/port');
  }

  
  
  String? plugin;
  String? pluginOpts;
  if (query != null) {
    final qp = Uri.splitQueryString(query);
    plugin = qp['plugin'];
    if (plugin != null && plugin.contains(';')) {
      final idx = plugin.indexOf(';');
      pluginOpts = plugin.substring(idx + 1);
      plugin = plugin.substring(0, idx);
    }
  }

  return VpnNode(
    id: 'ss_${_id(uri)}',
    name: fragment ?? host,
    address: host,
    port: port,
    protocol: VpnProtocol.shadowsocks,
    rawUri: uri,
    params: {
      'method': method,
      'password': password,
      if (plugin != null) 'plugin': plugin,
      if (pluginOpts != null) 'pluginOpts': pluginOpts,
    },
  );
}

String? _tryB64Decode(String s) {
  try {
    return utf8.decode(base64.decode(_b64Pad(s)));
  } catch (_) {
    return null;
  }
}

VpnNode _parseShadowsocksR(String uri) {
  final raw = uri.substring('ssr://'.length).trim();
  final decoded = _tryB64Decode(raw);
  if (decoded == null) {
    throw UriParseException('SSR: невалидный base64');
  }

  
  String main = decoded;
  String? paramsRaw;
  final qIdx = decoded.indexOf('/?');
  if (qIdx >= 0) {
    main = decoded.substring(0, qIdx);
    paramsRaw = decoded.substring(qIdx + 2);
  }

  final parts = main.split(':');
  if (parts.length < 6) {
    throw UriParseException('SSR: ожидается 6 полей host:port:proto:method:obfs:pass');
  }

  final host = parts[0];
  final port = int.tryParse(parts[1]) ?? 0;
  final protocol = parts[2];
  final method = parts[3];
  final obfs = parts[4];
  final passwordB64 = parts[5];
  final password = _tryB64Decode(passwordB64) ?? passwordB64;

  if (host.isEmpty || port == 0) {
    throw UriParseException('SSR: пустой host или port');
  }

  
  String remarks = host;
  String obfsParam = '';
  String protoParam = '';
  String group = '';
  if (paramsRaw != null) {
    final qp = Uri.splitQueryString(paramsRaw);
    obfsParam  = _tryB64Decode(qp['obfsparam']  ?? '') ?? '';
    protoParam = _tryB64Decode(qp['protoparam'] ?? '') ?? '';
    final r    = _tryB64Decode(qp['remarks']    ?? '');
    if (r != null && r.isNotEmpty) remarks = r;
    group      = _tryB64Decode(qp['group']      ?? '') ?? '';
  }

  return VpnNode(
    id: 'ssr_${_id(uri)}',
    name: remarks,
    address: host,
    port: port,
    protocol: VpnProtocol.unknown, 
    rawUri: uri,
    params: {
      'kind': 'ssr',
      'method': method,
      'password': password,
      'protocol': protocol,
      'protoParam': protoParam,
      'obfs': obfs,
      'obfsParam': obfsParam,
      'group': group,
    },
  );
}

VpnNode _parseSocks(String uri) {
  final u = Uri.parse(uri);
  final host = u.host;
  final port = u.port == 0 ? 1080 : u.port;
  String? user, pass;
  if (u.userInfo.isNotEmpty) {
    final ui = u.userInfo.split(':');
    user = Uri.decodeComponent(ui[0]);
    if (ui.length > 1) pass = Uri.decodeComponent(ui.sublist(1).join(':'));
  }
  final name = u.fragment.isNotEmpty ? Uri.decodeComponent(u.fragment) : host;

  return VpnNode(
    id: 'socks_${_id(uri)}',
    name: name,
    address: host,
    port: port,
    protocol: VpnProtocol.socks,
    rawUri: uri,
    params: {'user': user, 'pass': pass},
  );
}

String _b64Pad(String s) {
  String x = s.replaceAll('-', '+').replaceAll('_', '/');
  while (x.length % 4 != 0) { x += '='; }
  return x;
}

String _id(String s) {
  
  int h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h.toRadixString(16);
}

String buildXrayConfig(VpnNode node, {bool packetSniffing = true, bool useMux = false}) {
  if (node.protocol == VpnProtocol.hysteria2) {
    throw UriParseException('HYSTERIA2 не использует xray-core - нужен hysteria-бинарь');
  }

  final outbound = _outboundFor(node, useMux: useMux);

  
  
  
  
  
  
  
  final cfg = {
    'log': {'loglevel': 'warning'},
    'inbounds': <Map<String, dynamic>>[],
    'outbounds': [
      outbound,
      {'tag': 'direct', 'protocol': 'freedom'},
      {'tag': 'block', 'protocol': 'blackhole'},
    ],
    'dns': {'servers': ['1.1.1.1', 'localhost']},
    'routing': {
      'domainStrategy': 'IPIfNonMatch',
      'rules': [
        {'type': 'field', 'ip': ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'], 'outboundTag': 'direct'},
      ],
    },
  };

  return jsonEncode(cfg);
}

Map<String, dynamic> _outboundFor(VpnNode n, {required bool useMux}) {
  switch (n.protocol) {
    case VpnProtocol.vless: return _vlessOutbound(n, useMux: useMux);
    case VpnProtocol.vmess: return _vmessOutbound(n, useMux: useMux);
    case VpnProtocol.trojan: return _trojanOutbound(n, useMux: useMux);
    case VpnProtocol.shadowsocks: return _ssOutbound(n);
    case VpnProtocol.socks: return _socksOutbound(n);
    default:
      throw UriParseException('Протокол ${n.protocolLabel} пока не поддержан');
  }
}

Map<String, dynamic> _vlessOutbound(VpnNode n, {required bool useMux}) {
  final p = n.params;
  final stream = _streamSettings(
    network: p['type'] ?? 'tcp',
    security: p['security'] ?? 'none',
    sni: p['sni'], fp: p['fp'], alpn: p['alpn'],
    pbk: p['pbk'], sid: p['sid'], spx: p['spx'],
    wsHost: p['host'], wsPath: p['path'], serviceName: p['serviceName'],
    headerType: p['headerType'],
  );
  return {
    'tag': 'proxy',
    'protocol': 'vless',
    'settings': {
      'vnext': [{
        'address': n.address, 'port': n.port,
        'users': [{
          'id': p['uuid'], 'encryption': p['encryption'] ?? 'none',
          'flow': p['flow'] ?? '', 'level': 8, 'security': 'auto',
        }],
      }],
    },
    'streamSettings': stream,
    'mux': {'enabled': useMux, 'concurrency': 8},
  };
}

Map<String, dynamic> _vmessOutbound(VpnNode n, {required bool useMux}) {
  final p = n.params;
  final stream = _streamSettings(
    network: p['type'] ?? 'tcp',
    security: p['tls'] == 'tls' ? 'tls' : 'none',
    sni: p['sni'], fp: p['fp'], alpn: p['alpn'],
    wsHost: p['host'], wsPath: p['path'], headerType: p['headerType'],
  );
  return {
    'tag': 'proxy',
    'protocol': 'vmess',
    'settings': {
      'vnext': [{
        'address': n.address, 'port': n.port,
        'users': [{
          'id': p['uuid'], 'alterId': p['aid'] ?? 0,
          'security': p['security'] ?? 'auto', 'level': 8,
        }],
      }],
    },
    'streamSettings': stream,
    'mux': {'enabled': useMux, 'concurrency': 8},
  };
}

Map<String, dynamic> _trojanOutbound(VpnNode n, {required bool useMux}) {
  final p = n.params;
  final stream = _streamSettings(
    network: p['type'] ?? 'tcp',
    security: 'tls',
    sni: p['sni'], fp: p['fp'], alpn: p['alpn'],
    allowInsecure: p['allowInsecure'] ?? false,
    wsHost: p['host'], wsPath: p['path'], serviceName: p['serviceName'],
  );
  return {
    'tag': 'proxy',
    'protocol': 'trojan',
    'settings': {
      'servers': [{
        'address': n.address, 'port': n.port,
        'password': p['password'], 'level': 8,
      }],
    },
    'streamSettings': stream,
    'mux': {'enabled': useMux, 'concurrency': 8},
  };
}

Map<String, dynamic> _ssOutbound(VpnNode n) {
  return {
    'tag': 'proxy',
    'protocol': 'shadowsocks',
    'settings': {
      'servers': [{
        'address': n.address, 'port': n.port,
        'method': n.params['method'], 'password': n.params['password'], 'level': 8,
      }],
    },
  };
}

Map<String, dynamic> _socksOutbound(VpnNode n) {
  final users = <Map<String, dynamic>>[];
  if (n.params['user'] != null) {
    users.add({'user': n.params['user'], 'pass': n.params['pass'] ?? '', 'level': 8});
  }
  return {
    'tag': 'proxy',
    'protocol': 'socks',
    'settings': {
      'servers': [{
        'address': n.address, 'port': n.port,
        if (users.isNotEmpty) 'users': users,
      }],
    },
  };
}

Map<String, dynamic> _streamSettings({
  required String network,
  required String security,
  String? sni, String? fp, String? alpn,
  String? pbk, String? sid, String? spx,
  String? wsHost, String? wsPath, String? serviceName, String? headerType,
  bool allowInsecure = false,
}) {
  final s = <String, dynamic>{'network': network, 'security': security};

  if (security == 'reality') {
    s['realitySettings'] = {
      'serverName': sni ?? '', 'fingerprint': fp ?? 'chrome',
      'publicKey': pbk ?? '', 'shortId': sid ?? '', 'spiderX': spx ?? '',
      'show': false,
    };
  } else if (security == 'tls') {
    s['tlsSettings'] = {
      'serverName': sni ?? '',
      'fingerprint': fp ?? 'chrome',
      if ((alpn ?? '').isNotEmpty) 'alpn': alpn!.split(','),
      'allowInsecure': allowInsecure,
    };
  }

  switch (network) {
    case 'ws':
      s['wsSettings'] = {
        'path': wsPath ?? '/',
        if ((wsHost ?? '').isNotEmpty) 'headers': {'Host': wsHost},
      };
      break;
    case 'grpc':
      s['grpcSettings'] = {'serviceName': serviceName ?? ''};
      break;
    case 'tcp':
      s['tcpSettings'] = {'header': {'type': headerType ?? 'none'}};
      break;
    case 'h2':
      s['httpSettings'] = {
        'host': wsHost != null && wsHost.isNotEmpty ? [wsHost] : [],
        'path': wsPath ?? '/',
      };
      break;
  }
  return s;
}

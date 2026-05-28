import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../main.dart';
import '../models/vpn_node.dart';
import 'market_api.dart' show kApiBase;

class FixAction {
  
  final FixActionType type;

  
  
  final String? key;

  
  final dynamic value;

  
  final String? targetCountry;

  
  final String label;

  
  final String explanation;

  FixAction({
    required this.type,
    required this.label,
    required this.explanation,
    this.key,
    this.value,
    this.targetCountry,
  });

  factory FixAction.fromJson(Map<String, dynamic> j) {
    final typeStr = (j['type'] ?? '').toString();
    final type = FixActionType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => FixActionType.no_change,
    );
    return FixAction(
      type: type,
      key: j['key']?.toString(),
      value: j['value'],
      targetCountry: j['target_country']?.toString(),
      label: (j['label'] ?? '').toString(),
      explanation: (j['explanation'] ?? '').toString(),
    );
  }
}

enum FixActionType {
  
  switch_setting,

  
  switch_dns,

  
  switch_server,

  
  no_change,
}

class FixPlan {
  
  final String diagnosis;

  
  final int confidence;

  
  final List<FixAction> actions;

  FixPlan({required this.diagnosis, required this.confidence, required this.actions});

  factory FixPlan.fromJson(Map<String, dynamic> j) {
    final list = (j['actions'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => FixAction.fromJson(m.cast<String, dynamic>()))
        .where((a) => a.type != FixActionType.no_change || (j['actions'] as List).length == 1)
        .toList();
    return FixPlan(
      diagnosis: (j['diagnosis'] ?? 'Не удалось определить причину').toString(),
      confidence: ((j['confidence'] as num?)?.toInt() ?? 50).clamp(0, 100),
      actions: list,
    );
  }
}

const Set<String> _allowedBoolKeys = {
  'useMux',
  'packetAnalysis',
  'blockAds',
  'bypassLan',
  'resolveDestination',
  'dnsFakeDns',
  'dnsTunHijackDns',
  'netAllowIpv6',
};

const Set<String> _allowedStringKeys = {
  'dns',
  'dnsRemote',
  'dnsDirect',
  'dnsEnhancedMode',
  'dnsProxyResolveMode',
  'ipv6Route',
};

class DiagnosticSnapshot {
  final String? currentServerName;
  final String? currentServerCountry;
  final String? currentServerAddress;
  final int? currentServerPort;
  final String? currentProtocol;

  
  final String status;

  
  final int rxRate;
  final int txRate;

  
  final int uptimeMs;

  
  final Map<String, dynamic> settings;

  
  final List<String> logsTail;

  
  
  final Map<String, dynamic> probes;

  DiagnosticSnapshot({
    required this.currentServerName,
    required this.currentServerCountry,
    required this.currentServerAddress,
    required this.currentServerPort,
    required this.currentProtocol,
    required this.status,
    required this.rxRate,
    required this.txRate,
    required this.uptimeMs,
    required this.settings,
    required this.logsTail,
    required this.probes,
  });

  Map<String, dynamic> toJson() => {
        'server': {
          'name': currentServerName,
          'country': currentServerCountry,
          'address': currentServerAddress,
          'port': currentServerPort,
          'protocol': currentProtocol,
        },
        'status': status,
        'rx_rate_bps': rxRate,
        'tx_rate_bps': txRate,
        'uptime_ms': uptimeMs,
        'settings': settings,
        'logs_tail': logsTail,
        'probes': probes,
      };
}

class AiFixer {
  
  
  
  static const Map<String, List<String>> _problemTargets = {
    'youtube':  ['www.youtube.com', 'youtubei.googleapis.com', 'i.ytimg.com'],
    'tiktok':   ['www.tiktok.com', 'v16-webapp.tiktok.com'],
    'discord':  ['discord.com', 'gateway.discord.gg'],
    'instagram':['www.instagram.com', 'i.instagram.com'],
    'telegram': ['core.telegram.org', 'web.telegram.org'],
    'roblox':   ['www.roblox.com', 'clientsettings.roblox.com'],
    'chatgpt':  ['chat.openai.com', 'api.openai.com'],
    'generic':  ['www.google.com', 'www.cloudflare.com'],
  };

  
  
  static Future<DiagnosticSnapshot> collect({
    required AppState state,
    required String problemKey,
  }) async {
    final node = state.activeNode;
    final s = state.settings;
    final stats = state.currentStats;

    
    final settingsBrief = <String, dynamic>{
      'dns': s.dns,
      'dnsRemote': s.dnsRemote,
      'dnsDirect': s.dnsDirect,
      'dnsFakeDns': s.dnsFakeDns,
      'dnsEnhancedMode': s.dnsEnhancedMode,
      'dnsProxyResolveMode': s.dnsProxyResolveMode,
      'useMux': s.useMux,
      'packetAnalysis': s.packetAnalysis,
      'blockAds': s.blockAds,
      'bypassLan': s.bypassLan,
      'netAllowIpv6': s.netAllowIpv6,
      'ipv6Route': s.ipv6Route,
      'killSwitch': s.killSwitch,
    };

    final targets = _problemTargets[problemKey] ?? _problemTargets['generic']!;
    final probes = await _runProbes(
      vpnHost: node?.address,
      vpnPort: node?.port,
      targets: targets,
    );

    final logs = _safeReadLogs(state);

    return DiagnosticSnapshot(
      currentServerName: node?.name,
      currentServerCountry: _countryFromName(node?.name),
      currentServerAddress: node?.address,
      currentServerPort: node?.port,
      currentProtocol: node?.protocol.name,
      status: state.status.name,
      rxRate: stats.rxRate,
      txRate: stats.txRate,
      uptimeMs: stats.uptimeMs,
      settings: settingsBrief,
      logsTail: logs,
      probes: probes,
    );
  }

  
  
  static Future<Map<String, dynamic>> _runProbes({
    required String? vpnHost,
    required int? vpnPort,
    required List<String> targets,
  }) async {
    final results = <String, dynamic>{};

    final futures = <Future>[];

    if (vpnHost != null && vpnPort != null && vpnHost.isNotEmpty) {
      futures.add(_tcpProbe(vpnHost, vpnPort).then((ms) {
        results['vpn_node_tcp_ms'] = ms;
      }));
    }

    for (final t in targets.take(3)) {
      futures.add(_tcpProbe(t, 443).then((ms) {
        (results['targets_tcp_ms'] ??= <String, dynamic>{})[t] = ms;
      }));
    }

    if (targets.isNotEmpty) {
      futures.add(_dnsProbe(targets.first).then((info) {
        results['dns_first_target'] = info;
      }));
    }

    await Future.wait(futures).timeout(
      const Duration(seconds: 5),
      onTimeout: () => <dynamic>[],
    );

    return results;
  }

  
  static Future<int> _tcpProbe(String host, int port) async {
    final sw = Stopwatch()..start();
    try {
      final s = await Socket.connect(host, port, timeout: const Duration(seconds: 3));
      sw.stop();
      s.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  
  static Future<Map<String, dynamic>> _dnsProbe(String host) async {
    final sw = Stopwatch()..start();
    try {
      final list = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 3));
      sw.stop();
      return {
        'ok': true,
        'ms': sw.elapsedMilliseconds,
        'addrs': list.take(3).map((a) => a.address).toList(),
      };
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  
  
  static List<String> _safeReadLogs(AppState state) {
    try {
      
      final dyn = state as dynamic;
      final raw = dyn.logBuffer ?? dyn.logs ?? dyn.recentLogs;
      if (raw is List) {
        return raw
            .map((e) => e.toString())
            .toList()
            .reversed
            .take(80)
            .toList()
            .reversed
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  
  static String? _countryFromName(String? name) {
    if (name == null || name.isEmpty) return null;
    final runes = name.runes.toList();
    if (runes.length >= 2 &&
        runes[0] >= 0x1F1E6 && runes[0] <= 0x1F1FF &&
        runes[1] >= 0x1F1E6 && runes[1] <= 0x1F1FF) {
      final a = String.fromCharCode(runes[0] - 0x1F1E6 + 65);
      final b = String.fromCharCode(runes[1] - 0x1F1E6 + 65);
      return '$a$b';
    }
    return null;
  }

  

  static const Duration _timeout = Duration(seconds: 30);

  
  
  static Future<FixPlan> requestFix({
    required DiagnosticSnapshot snapshot,
    required String userMessage,
    required String problemKey,
    int? telegramId,
  }) async {
    final body = jsonEncode({
      'user_message': userMessage,
      'problem_key': problemKey,
      if (telegramId != null) 'telegram_id': telegramId,
      'snapshot': snapshot.toJson(),
    });

    final r = await http
        .post(
          Uri.parse('$kApiBase/ai/fix'),
          headers: const {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(_timeout);

    if (r.statusCode < 200 || r.statusCode >= 300) {
      String msg;
      try {
        msg = ((jsonDecode(r.body) as Map)['detail'] ?? r.body).toString();
      } catch (_) {
        msg = r.body;
      }
      throw Exception('AI fix failed (${r.statusCode}): $msg');
    }

    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return FixPlan.fromJson(j);
  }

  

  
  
  
  
  
  static Future<bool> applyAction({
    required AppState state,
    required FixAction action,
  }) async {
    switch (action.type) {
      case FixActionType.no_change:
        return false;

      case FixActionType.switch_setting:
        return _applySettingChange(state, action.key, action.value);

      case FixActionType.switch_dns:
        
        final v = action.value?.toString();
        if (v == null || v.isEmpty) return false;
        final s = _cloneSettings(state.settings);
        s.dns = v;
        s.dnsRemote = _wrapDnsForRemote(v);
        s.dnsDirect = v;
        state.updateSettings(s);
        return true;

      case FixActionType.switch_server:
        return _applyServerSwitch(state, action.targetCountry);
    }
  }

  static bool _applySettingChange(AppState state, String? key, dynamic value) {
    if (key == null || value == null) return false;

    final s = _cloneSettings(state.settings);
    var changed = false;

    if (_allowedBoolKeys.contains(key) && value is bool) {
      changed = _setBoolField(s, key, value);
    } else if (_allowedStringKeys.contains(key) && value is String) {
      changed = _setStringField(s, key, value);
    } else {
      
      if (kDebugMode) {
        debugPrint('AI fix: rejected setting $key=$value (not in allowlist)');
      }
      return false;
    }

    if (changed) state.updateSettings(s);
    return changed;
  }

  
  
  
  static bool _applyServerSwitch(AppState state, String? targetCountry) {
    final current = state.activeNode;
    VpnNode? pick;

    if (targetCountry != null && targetCountry.length == 2) {
      final cc = targetCountry.toUpperCase();
      for (final g in state.groups) {
        for (final n in g.nodes) {
          if (n.id == current?.id) continue;
          final nc = _countryFromName(n.name);
          if (nc != null && nc.toUpperCase() == cc) {
            pick = n;
            break;
          }
        }
        if (pick != null) break;
      }
    }

    
    if (pick == null) {
      outer:
      for (final g in state.groups) {
        for (final n in g.nodes) {
          if (n.id != current?.id) {
            pick = n;
            break outer;
          }
        }
      }
    }

    if (pick == null) return false;
    
    state.connect(pick);
    return true;
  }

  

  
  
  
  
  
  
  
  static AppSettings _cloneSettings(AppSettings s) => s;

  static bool _setBoolField(AppSettings s, String key, bool v) {
    switch (key) {
      case 'useMux':              if (s.useMux == v) return false; s.useMux = v; return true;
      case 'packetAnalysis':      if (s.packetAnalysis == v) return false; s.packetAnalysis = v; return true;
      case 'blockAds':            if (s.blockAds == v) return false; s.blockAds = v; return true;
      case 'bypassLan':           if (s.bypassLan == v) return false; s.bypassLan = v; return true;
      case 'resolveDestination':  if (s.resolveDestination == v) return false; s.resolveDestination = v; return true;
      case 'dnsFakeDns':          if (s.dnsFakeDns == v) return false; s.dnsFakeDns = v; return true;
      case 'dnsTunHijackDns':     if (s.dnsTunHijackDns == v) return false; s.dnsTunHijackDns = v; return true;
      case 'netAllowIpv6':        if (s.netAllowIpv6 == v) return false; s.netAllowIpv6 = v; return true;
    }
    return false;
  }

  static bool _setStringField(AppSettings s, String key, String v) {
    switch (key) {
      case 'dns':                 if (s.dns == v) return false; s.dns = v; return true;
      case 'dnsRemote':           if (s.dnsRemote == v) return false; s.dnsRemote = v; return true;
      case 'dnsDirect':           if (s.dnsDirect == v) return false; s.dnsDirect = v; return true;
      case 'dnsEnhancedMode':     if (s.dnsEnhancedMode == v) return false; s.dnsEnhancedMode = v; return true;
      case 'dnsProxyResolveMode': if (s.dnsProxyResolveMode == v) return false; s.dnsProxyResolveMode = v; return true;
      case 'ipv6Route':           if (s.ipv6Route == v) return false; s.ipv6Route = v; return true;
    }
    return false;
  }

  
  
  static String _wrapDnsForRemote(String v) {
    final lower = v.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('tls://') ||
        lower.startsWith('tcp://') ||
        lower.startsWith('udp://') ||
        lower.startsWith('quic://')) {
      return v;
    }
    return 'tcp://$v';
  }
}

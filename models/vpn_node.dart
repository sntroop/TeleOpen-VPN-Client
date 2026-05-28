import 'dart:convert';

enum VpnProtocol { vless, vmess, trojan, hysteria2, shadowsocks, socks, tuic, wireguard, unknown }

extension VpnProtocolX on VpnProtocol {
  String get label => switch (this) {
        VpnProtocol.vless       => 'VLESS',
        VpnProtocol.vmess       => 'VMESS',
        VpnProtocol.trojan      => 'TROJAN',
        VpnProtocol.hysteria2   => 'HYSTERIA2',
        VpnProtocol.shadowsocks => 'SS',
        VpnProtocol.socks       => 'SOCKS',
        VpnProtocol.tuic        => 'TUIC',
        VpnProtocol.wireguard   => 'WG',
        VpnProtocol.unknown     => '?',
      };

  static VpnProtocol fromScheme(String s) {
    final l = s.toLowerCase();
    if (l.startsWith('vless'))         return VpnProtocol.vless;
    if (l.startsWith('vmess'))         return VpnProtocol.vmess;
    if (l.startsWith('trojan'))        return VpnProtocol.trojan;
    if (l.startsWith('hysteria2') ||
        l.startsWith('hy2'))           return VpnProtocol.hysteria2;
    if (l.startsWith('ss:') || l == 'ss') return VpnProtocol.shadowsocks;
    if (l.startsWith('socks'))         return VpnProtocol.socks;
    if (l.startsWith('tuic'))          return VpnProtocol.tuic;
    if (l.startsWith('wg') ||
        l.startsWith('wireguard'))     return VpnProtocol.wireguard;
    return VpnProtocol.unknown;
  }
}

class VpnNode {
  final String id;
  String name;
  final String address;
  final int port;
  final VpnProtocol protocol;
  final String rawUri;
  final Map<String, dynamic> params;

  int? pingMs;
  bool isFavorite;
  String? groupId;

  VpnNode({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.protocol,
    required this.rawUri,
    this.params = const {},
    this.pingMs,
    this.isFavorite = false,
    this.groupId,
  });

  String get protocolLabel => protocol.label;

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'address': address, 'port': port,
        'protocol': protocol.name, 'rawUri': rawUri, 'params': params,
        
        
        'isFavorite': isFavorite, 'groupId': groupId,
      };

  static VpnNode fromJson(Map<String, dynamic> j) => VpnNode(
        id: j['id'],
        name: j['name'],
        address: j['address'],
        port: j['port'],
        protocol: VpnProtocol.values.firstWhere(
          (p) => p.name == j['protocol'],
          orElse: () => VpnProtocol.unknown,
        ),
        rawUri: j['rawUri'] ?? '',
        params: (j['params'] as Map?)?.cast<String, dynamic>() ?? {},
        
        isFavorite: j['isFavorite'] ?? false,
        groupId: j['groupId'],
      );
}

class VpnGroup {
  final String id;
  String title;
  String? subtitle;
  String? sourceUrl;
  DateTime? updatedAt;
  List<VpnNode> nodes;

  
  
  int? trafficUpload;    
  int? trafficDownload;  
  int? trafficTotal;     
  int? trafficExpire;    

  
  String? description;

  
  bool isCollapsed;

  VpnGroup({
    required this.id,
    required this.title,
    this.subtitle,
    this.sourceUrl,
    this.updatedAt,
    required this.nodes,
    this.trafficUpload,
    this.trafficDownload,
    this.trafficTotal,
    this.trafficExpire,
    this.description,
    this.isCollapsed = false,
  });

  

  
  int? get trafficUsed {
    if (trafficUpload == null && trafficDownload == null) return null;
    return (trafficUpload ?? 0) + (trafficDownload ?? 0);
  }

  
  DateTime? get expiresAt => trafficExpire != null
      ? DateTime.fromMillisecondsSinceEpoch(trafficExpire! * 1000)
      : null;

  
  int? get daysLeft {
    final exp = expiresAt;
    if (exp == null) return null;
    return exp.difference(DateTime.now()).inDays;
  }

  
  double? get trafficFraction {
    final used = trafficUsed;
    final total = trafficTotal;
    if (used == null || total == null || total == 0) return null;
    return (used / total).clamp(0.0, 1.0);
  }

  
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'sourceUrl': sourceUrl,
        'updatedAt': updatedAt?.toIso8601String(),
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'trafficUpload': trafficUpload,
        'trafficDownload': trafficDownload,
        'trafficTotal': trafficTotal,
        'trafficExpire': trafficExpire,
        'description': description,
        
      };

  static VpnGroup fromJson(Map<String, dynamic> j) => VpnGroup(
        id: j['id'],
        title: j['title'],
        subtitle: j['subtitle'],
        sourceUrl: j['sourceUrl'],
        updatedAt: j['updatedAt'] != null ? DateTime.tryParse(j['updatedAt']) : null,
        nodes: ((j['nodes'] as List?) ?? [])
            .map((e) => VpnNode.fromJson(e as Map<String, dynamic>))
            .toList(),
        trafficUpload:   j['trafficUpload'] as int?,
        trafficDownload: j['trafficDownload'] as int?,
        trafficTotal:    j['trafficTotal'] as int?,
        trafficExpire:   j['trafficExpire'] as int?,
        description:     j['description'] as String?,
      );

  static String encode(List<VpnGroup> groups) =>
      jsonEncode(groups.map((g) => g.toJson()).toList());

  static List<VpnGroup> decode(String s) {
    if (s.isEmpty) return [];
    final list = jsonDecode(s) as List;
    return list.map((e) => VpnGroup.fromJson(e as Map<String, dynamic>)).toList();
  }
}

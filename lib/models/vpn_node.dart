// lib/models/vpn_node.dart

import 'dart:convert';

import 'package:crypto/crypto.dart';

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
        l.startsWith('hy2')) {
      return VpnProtocol.hysteria2;
    }
    if (l.startsWith('ss:') || l == 'ss') return VpnProtocol.shadowsocks;
    if (l.startsWith('socks'))         return VpnProtocol.socks;
    if (l.startsWith('tuic'))          return VpnProtocol.tuic;
    if (l.startsWith('wg') ||
        l.startsWith('wireguard')) {
      return VpnProtocol.wireguard;
    }
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

  /// Исходный полный JSON-конфиг xray для этой ноды (если подписка отдала
  /// готовые конфиги, а не share-ссылки). Когда он есть — при подключении мы
  /// отдаём его ядру КАК ЕСТЬ (через xrayConfigForNode), а не пересобираем из
  /// params. Это сохраняет транспортные поля (grpc serviceName, tls alpn,
  /// xhttp, spiderX и т.п.), которые терялись при round-trip в vless://.
  /// null для нод из vless://-ссылок — для них конфиг строит buildXrayConfig.
  String? rawConfig;

  int? pingMs;
  bool isFavorite;
  String? groupId;

  /// Хэш URI этого сервера в маркете (sha256(uri)[:16]), который проставляет
  /// бэкенд при выдаче подписки. Нужен для жалобы на конкретную ноду
  /// (`/market/report_node`). Заполняется при добавлении market-подписки;
  /// для старых сохранённых нод null — тогда используется фолбэк-getter ниже.
  String? marketUriHash;

  VpnNode({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.protocol,
    required this.rawUri,
    this.params = const {},
    this.rawConfig,
    this.pingMs,
    this.isFavorite = false,
    this.groupId,
    this.marketUriHash,
  });

  String get protocolLabel => protocol.label;

  /// Хэш ноды для market-жалоб. Предпочитаем точный хэш от бэка
  /// (`marketUriHash`), но для подписок, добавленных до появления этого поля,
  /// считаем тот же sha256(uri)[:16] локально из rawUri. В подавляющем
  /// большинстве случаев rawUri идентичен исходному URI, так что хэши совпадут.
  String get reportUriHash {
    final h = marketUriHash;
    if (h != null && h.isNotEmpty) return h;
    return sha256.convert(utf8.encode(rawUri)).toString().substring(0, 16);
  }

  /// MED-4: true, если у ноды отключена проверка TLS-сертификата
  /// (insecure=1 / allowInsecure=1). Такой сервер уязвим к MITM — UI должен
  /// показывать предупреждающий бейдж.
  bool get hasInsecureTls =>
      params['insecure'] == true || params['allowInsecure'] == true;

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'address': address, 'port': port,
        'protocol': protocol.name, 'rawUri': rawUri, 'params': params,
        if (rawConfig != null) 'rawConfig': rawConfig,
        // pingMs намеренно не сериализуем — рантайм-метрика, иначе показывает
        // устаревший пинг с прошлого запуска как актуальный
        'isFavorite': isFavorite, 'groupId': groupId,
        'marketUriHash': marketUriHash,
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
        rawConfig: j['rawConfig'] as String?,
        // pingMs не читаем — рантайм-значение
        isFavorite: j['isFavorite'] ?? false,
        groupId: j['groupId'],
        marketUriHash: j['marketUriHash'],
      );
}

class VpnGroup {
  final String id;
  String title;
  String? subtitle;
  String? sourceUrl;
  DateTime? updatedAt;
  List<VpnNode> nodes;

  // ── данные из subscription-userinfo заголовка ─────────────────────────────
  // upload / download / total / expire (unix timestamp) — всё в байтах/секундах
  int? trafficUpload;    // upload=<bytes>
  int? trafficDownload;  // download=<bytes>
  int? trafficTotal;     // total=<bytes>
  int? trafficExpire;    // expire=<unix timestamp>

  // дополнительное описание из заголовка или кастомное
  String? description;

  // ── живые поля из teleopen:// (резолв /v2/resolve?format=json) ─────────────
  String? renewUrl;      // диплинк «Продлить» в бота продавца
  String? brandColor;    // акцент бренда продавца, hex '#RRGGBB'

  // ── брендинг подписки из маркета ──────────────────────────────────────────
  String? iconUrl;       // логотип автора (показываем кругло в хедере группы)
  String? contactUrl;    // t.me-ссылка на автора/канал (кнопка «Contact»)

  // состояние UI — свёрнута ли группа
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
    this.renewUrl,
    this.brandColor,
    this.iconUrl,
    this.contactUrl,
    this.isCollapsed = false,
  });

  // ── удобные геттеры ───────────────────────────────────────────────────────

  /// Израсходовано байт (upload + download)
  int? get trafficUsed {
    if (trafficUpload == null && trafficDownload == null) return null;
    return (trafficUpload ?? 0) + (trafficDownload ?? 0);
  }

  /// Дата истечения подписки
  DateTime? get expiresAt => trafficExpire != null
      ? DateTime.fromMillisecondsSinceEpoch(trafficExpire! * 1000)
      : null;

  /// Дней до истечения (null если нет данных)
  int? get daysLeft {
    final exp = expiresAt;
    if (exp == null) return null;
    return exp.difference(DateTime.now()).inDays;
  }

  /// Доля использованного трафика [0.0 .. 1.0]
  double? get trafficFraction {
    final used = trafficUsed;
    final total = trafficTotal;
    if (used == null || total == null || total == 0) return null;
    return (used / total).clamp(0.0, 1.0);
  }

  // ── сериализация ──────────────────────────────────────────────────────────
  /// Метаданные группы БЕЗ списка нод. Нужно для стримингового хранилища
  /// (NodeStore): там ноды пишутся отдельными записями, и материализовать
  /// огромный массив `nodes` (до десятков тысяч) в памяти нельзя.
  Map<String, dynamic> toMetaJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'sourceUrl': sourceUrl,
        'updatedAt': updatedAt?.toIso8601String(),
        'trafficUpload': trafficUpload,
        'trafficDownload': trafficDownload,
        'trafficTotal': trafficTotal,
        'trafficExpire': trafficExpire,
        'description': description,
        'renewUrl': renewUrl,
        'brandColor': brandColor,
        'iconUrl': iconUrl,
        'contactUrl': contactUrl,
        // isCollapsed — не сохраняем, сбрасывается при перезапуске
      };

  Map<String, dynamic> toJson() => {
        ...toMetaJson(),
        'nodes': nodes.map((n) => n.toJson()).toList(),
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
        renewUrl:        j['renewUrl'] as String?,
        brandColor:      j['brandColor'] as String?,
        iconUrl:         j['iconUrl'] as String?,
        contactUrl:      j['contactUrl'] as String?,
      );

  static String encode(List<VpnGroup> groups) =>
      jsonEncode(groups.map((g) => g.toJson()).toList());

  static List<VpnGroup> decode(String s) {
    if (s.isEmpty) return [];
    final list = jsonDecode(s) as List;
    return list.map((e) => VpnGroup.fromJson(e as Map<String, dynamic>)).toList();
  }
}

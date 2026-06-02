// lib/models/routing_rule.dart
//
// Пользовательское правило маршрутизации (как в Happ): сопоставляем трафик по
// geosite-категории / geoip-стране / домену / IP-CIDR и направляем в proxy,
// direct или block. Список правил хранится в AppSettings (JSON), уходит в натив
// через toCoreConfig() и применяется в HysteriaTunVpnService.ensureTunInbound.

/// Чем сопоставляем трафик.
enum RuleKind { geosite, geoip, domain, ip }

/// Куда направляем совпавший трафик (= xray outboundTag).
enum RuleAction { proxy, direct, block }

extension RuleKindX on RuleKind {
  String get id => switch (this) {
        RuleKind.geosite => 'geosite',
        RuleKind.geoip => 'geoip',
        RuleKind.domain => 'domain',
        RuleKind.ip => 'ip',
      };

  /// Короткая подпись для UI.
  String get label => switch (this) {
        RuleKind.geosite => 'Geosite (категория доменов)',
        RuleKind.geoip => 'GeoIP (страна)',
        RuleKind.domain => 'Домен',
        RuleKind.ip => 'IP / CIDR',
      };

  String get hint => switch (this) {
        RuleKind.geosite => 'netflix, telegram, category-ads-all',
        RuleKind.geoip => 'ru, us, cn',
        RuleKind.domain => 'example.com или *.example.com',
        RuleKind.ip => '8.8.8.8 или 10.0.0.0/8',
      };

  static RuleKind fromId(String s) =>
      RuleKind.values.firstWhere((k) => k.id == s, orElse: () => RuleKind.domain);
}

extension RuleActionX on RuleAction {
  String get id => switch (this) {
        RuleAction.proxy => 'proxy',
        RuleAction.direct => 'direct',
        RuleAction.block => 'block',
      };

  String get label => switch (this) {
        RuleAction.proxy => 'Через VPN (proxy)',
        RuleAction.direct => 'Напрямую (direct)',
        RuleAction.block => 'Блокировать (block)',
      };

  static RuleAction fromId(String s) =>
      RuleAction.values.firstWhere((a) => a.id == s, orElse: () => RuleAction.proxy);
}

class RoutingRule {
  RuleKind kind;
  String value;
  RuleAction action;
  bool enabled;

  RoutingRule({
    required this.kind,
    required this.value,
    this.action = RuleAction.proxy,
    this.enabled = true,
  });

  RoutingRule copy() =>
      RoutingRule(kind: kind, value: value, action: action, enabled: enabled);

  Map<String, dynamic> toJson() => {
        'kind': kind.id,
        'value': value,
        'action': action.id,
        'enabled': enabled,
      };

  factory RoutingRule.fromJson(Map<String, dynamic> j) => RoutingRule(
        kind: RuleKindX.fromId((j['kind'] as String?) ?? 'domain'),
        value: (j['value'] as String?) ?? '',
        action: RuleActionX.fromId((j['action'] as String?) ?? 'proxy'),
        enabled: (j['enabled'] as bool?) ?? true,
      );

  /// Человекочитаемое представление "geosite:netflix → proxy".
  String get display {
    final prefix = switch (kind) {
      RuleKind.geosite => 'geosite:',
      RuleKind.geoip => 'geoip:',
      _ => '',
    };
    return '$prefix$value';
  }
}

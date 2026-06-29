// lib/state/app_settings.dart
//
// Модель пользовательских настроек приложения (соединение, маршрутизация,
// DNS, локальные порты, External Controller, функции Meta). Сериализуется в
// SharedPreferences и в Map для нативного ядра (mihomo/clash.meta).
//
// Вынесено из main.dart при разбиении монолита — поведение не менялось.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/routing_rule.dart';

/// Тип измерения пинга нод.
/// tcp  — handshake до host:port (быстро, без ядра);
/// http — реальная задержка через туннель (xray measureOutboundDelay);
/// udp  — best-effort датаграмм-зонд до host:port.
/// get  — прямой HTTP(S) GET до host:port.
const kPingModes = <String>['TCP', 'GET', 'HTTP', 'UDP'];

/// Варианты интервала автообновления подписок (часы; 0 = выключено).
const kSubUpdateIntervals = <int>[0, 6, 12, 24, 48];

/// ByeDPI: режим списка хостов для десинхронизации.
const kBdpiHostsModes = <String>['Нет', 'Белый список', 'Чёрный список'];

/// ByeDPI: методы десинхронизации (как в ByeByeDPI).
const kBdpiDesyncMethods = <String>[
  'Disorder',
  'Split',
  'None',
  'Fake',
  'Out-of-band',
  'Disorder out-of-band',
];

/// Разбивает строку аргументов ciadpi в argv, уважая кавычки (как shell).
/// Нужно, потому что стратегии содержат списки в кавычках, напр.
/// `-H:"googlevideo.com youtu.be ..."` — пробелы внутри кавычек не разделяют.
List<String> tokenizeByeDpiArgs(String raw) {
  final tokens = <String>[];
  final sb = StringBuffer();
  bool inToken = false;
  String? quote;
  for (int i = 0; i < raw.length; i++) {
    final ch = raw[i];
    if (quote != null) {
      if (ch == quote) {
        quote = null;
      } else {
        sb.write(ch);
      }
      inToken = true;
    } else if (ch == '"' || ch == "'") {
      quote = ch;
      inToken = true;
    } else if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
      if (inToken) {
        tokens.add(sb.toString());
        sb.clear();
        inToken = false;
      }
    } else {
      sb.write(ch);
      inToken = true;
    }
  }
  if (inToken) tokens.add(sb.toString());
  return tokens;
}

/// Стандартный набор приватных/служебных подсетей, исключаемых из туннеля.
const List<String> kDefaultExcludedRoutes = [
  '10.0.0.0/8',
  '100.64.0.0/10',
  '172.16.0.0/12',
  '192.168.0.0/16',
  '169.254.0.0/16',
  '224.0.0.0/4',
  '255.255.255.255/32',
  '::1/128',
  'fc00::/7',
  'fe80::/10',
  'ff00::/8',
];

class AppSettings {
  // ── Соединение ──────────────────────────────────────────────────────────
  bool killSwitch;
  bool autoConnect;
  bool autoConnectOnBoot; // NEW: автоподключение при загрузке устройства
  bool autoFailover;
  String dns;

  // ── Продвинутое ─────────────────────────────────────────────────────────
  bool packetAnalysis;
  bool useMux;
  bool xrayTunMode; // NEW: xray управляет TUN напрямую (без tun2socks)
  bool keepDeviceAwake; // NEW: wakelock для Xiaomi/HyperOS
  int memoryLimitMB; // NEW: лимит памяти (40/60/80/100/150/0=unlimited)
  bool proxyOnlyMode; // NEW: только локальный прокси без VPN туннеля
  bool routeLanThroughProxy; // NEW: форсировать локальный трафик через прокси

  // ── INCY round 2 ──────────────────────────────────────────────────────────
  String tunnelMode; // 'tun_proxy' | 'tun_only' | 'proxy_only'
  bool blockUdp; // блокировать UDP (ломает QUIC/DoH-UDP/звонки/игры)
  bool showSpeedInNotification; // показывать ↓/↑ скорость в уведомлении
  int connIdleTimeout; // таймаут простоя соединения, сек (xray policy connIdle)
  int maxTcpConns; // макс. одновременных TCP
  int maxUdpConns; // макс. одновременных UDP
  List<String> excludedRoutes; // IP-CIDR, исключённые из туннеля
  String logRetention; // '1h' | '6h' | '24h' | '7d' | 'all'
  String socksBindAddress; // адрес локального socks (127.0.0.1 / 0.0.0.0)
  int socksPort; // порт локального socks (1024..65535)
  String ipType; // 'ipv4' | 'ipv6' | 'auto'

  // ── Пинг ──────────────────────────────────────────────────────────────────
  String pingMode; // 'TCP' | 'GET' | 'HTTP' | 'UDP' (см. kPingModes)

  // ── Подписки ────────────────────────────────────────────────────────────
  bool subAutoUpdate;
  int subUpdateHours; // 0 = выкл (см. kSubUpdateIntervals)

  // ── Маршрутизация ────────────────────────────────────────────────────────
  String region;
  String balancerStrategy;
  bool blockAds;
  bool bypassLan;
  bool resolveDestination;
  String ipv6Route;
  List<RoutingRule> routingRules;

  // ══════════════════════════════════════════════════════════════════════════
  // Расширенные настройки (mihomo / clash.meta).
  // Строковые поля используют sentinel-значение 'Не менять' = не подмешивать
  // в конфиг ядра (оставлять как в подписке).
  // ══════════════════════════════════════════════════════════════════════════

  // ── DNS: базовые (как было в dns_screen) ───────────────────────────────
  String dnsRemote;
  String dnsRemoteDomainStrategy;
  bool dnsFakeDns;
  String dnsDirect;
  String dnsDirectDomainStrategy;

  // ── DNS: сервер ─────────────────────────────────────────────────────────
  bool dnsTunHijackDns;
  bool dnsAllowIncomingDomains;
  String dnsTestDomain;
  String dnsTtl;
  bool dnsEnableRules;
  bool dnsDirectStreamEcs;
  String dnsProxyResolveMode; // FakeIP / RealIP

  // ── DNS: переопределение (sentinel 'Не менять') ────────────────────────
  String dnsPreferHttp3;
  String dnsRespectRules;
  String dnsUseSystemDns;
  String dnsIpv6Override;
  String dnsUseHosts;
  String dnsEnhancedMode; // fake-ip / redir-host / Не менять
  String dnsNameserver;
  String dnsFallbackNameserver;
  String dnsDefaultNameserver;
  String dnsFakeIpFilter;
  String dnsFakeIpFilterMode; // blacklist / whitelist / Не менять
  String dnsFallbackGeoip;
  String dnsFallbackGeoipCode;
  String dnsFallbackDomain;
  String dnsFallbackIpcidr;
  String dnsNameserverPolicy;

  // ── Сеть (интеграция с VpnService) ─────────────────────────────────────
  bool netRouteSystemTraffic;
  bool netBypassPrivate;
  bool netHijackDns;
  bool netAllowBypass;
  bool netAllowIpv6;
  bool netSystemProxy;

  // ── Локальные порты (mixin) ────────────────────────────────────────────
  String portHttp;
  String portSocks;
  String portRedir;
  String portTproxy;
  String portMixed;
  String portAuth;
  String portAllowLan;
  String portIpv6;
  String portBindAddress;

  // ── Авторизация локальных проксиков (NEW: SOCKS5/HTTP auth) ───────────
  bool socksAuthEnabled; // включить авторизацию SOCKS5
  String socksAuthUsername; // логин для SOCKS5
  String socksAuthPassword; // пароль для SOCKS5
  bool httpAuthEnabled; // включить авторизацию HTTP (при hotspot)
  String httpAuthUsername; // логин для HTTP
  String httpAuthPassword; // пароль для HTTP

  // ── External Controller ────────────────────────────────────────────────
  String ecAddress;
  String ecAddressTls;
  String ecAllowOrigins;
  String ecAllowPrivateNetwork;
  String ecSecret;
  String ecMode;
  String ecLogLevel;
  String ecHosts;

  // ── Функции Meta ───────────────────────────────────────────────────────
  String metaUnifiedDelay;
  String metaGeoMode;
  String metaMptcp;
  String metaFindProcess;
  String metaStrategy;
  String metaSniffHttpPorts;
  String metaSniffHttpOverride;
  String metaSniffTlsPorts;
  String metaSniffTlsOverride;
  String metaSniffQuicPorts;
  String metaSniffQuicOverride;
  String metaForceDnsMapping;
  String metaParsePureIp;
  String metaOverrideDestination;
  String metaForceDomain;
  String metaSkipDomain;
  String metaSkipSrc;
  String metaSkipDst;
  String metaGeoipPath; // путь до импортированного файла
  String metaGeositePath;
  String metaCountryPath;
  String metaAsnPath;

  // ══════════════════════════════════════════════════════════════════════════
  // Обход DPI (ByeDPI / ByeByeDPI).
  // ВАЖНО: эти приёмы реализует НАТИВНЫЙ движок ByeDPI (локальная переписка
  // TCP/UDP-пакетов). Ядро xray/mihomo, через которое сейчас идёт трафик, их
  // НЕ применяет — как и «Трюки TLS» / часть «Функций Meta». Значения здесь
  // сохраняются и уходят в нативный слой под ключами bdpi_*; реальный эффект
  // появится после интеграции движка ByeDPI на нативной стороне.
  // ══════════════════════════════════════════════════════════════════════════

  // ── Прокси ──────────────────────────────────────────────────────────────
  String bdpiMaxConnections; // число (по умолчанию 512)
  String bdpiBufferSize; // байты (по умолчанию 16384)
  bool bdpiNoDomain; // «Без домена»
  bool bdpiTcpFastOpen; // TCP Fast Open

  // ── Десинхронизация ───────────────────────────────────────────────────────
  String bdpiHostsMode; // 'Нет' | 'Белый список' | 'Чёрный список'
  String bdpiDefaultTtl; // TTL по умолчанию (любое число)
  String bdpiDesyncMethod; // см. kBdpiDesyncMethods
  String bdpiSplitPosition; // позиция разделения (любое число)
  bool bdpiSplitAtHost; // «Разделить в хосте»
  bool bdpiDropSack; // «Отбрасывать SACK»

  // ── Протоколы ─────────────────────────────────────────────────────────────
  bool bdpiDesyncHttp;
  bool bdpiDesyncHttps;
  bool bdpiDesyncUdp;

  // ── HTTP ────────────────────────────────────────────────────────────────
  bool bdpiHostMixedCase; // смешанный регистр хоста
  bool bdpiDomainMixedCase; // смешанный регистр домена
  bool bdpiHostRemoveSpaces; // удалить пробелы из хоста

  // ── HTTPS ───────────────────────────────────────────────────────────────
  bool bdpiTlsRecordSplit; // разделить TLS-запись
  String bdpiTlsRecordSplitPos; // позиция разделения TLS-записи (любое число)
  bool bdpiTlsRecordSplitAtSni; // разделить TLS-запись в SNI

  // ── UDP ─────────────────────────────────────────────────────────────────
  String bdpiFakeUdpCount; // количество поддельных UDP (любое число)

  // ── Стратегия (сырые аргументы ciadpi) ──────────────────────────────────
  // Если непусто — этой строкой аргументов ЗАМЕНЯЕТ всё, что собрали тумблеры
  // выше (buildByeDpiArgs возвращает её, токенизировав). Сюда пользователь
  // кладёт стратегию, которую нашёл/составил сам (напр. в TG). Пусто — args
  // строятся из тумблеров.
  String bdpiStrategy;

  // ── Режим ───────────────────────────────────────────────────────────────
  // Если true — «Подключить» поднимает ОТДЕЛЬНЫЙ режим обхода DPI (ciadpi
  // напрямую, без VPN-сервера) вместо xray/hysteria. Только в этом режиме
  // приёмы десинхронизации реально применяются.
  bool bdpiModeEnabled;

  AppSettings({
    this.killSwitch = false,
    this.autoConnect = false,
    this.autoConnectOnBoot = false, // NEW
    this.autoFailover = false,
    this.dns = '1.1.1.1',
    this.packetAnalysis = true,
    this.useMux = false,
    this.xrayTunMode = false, // NEW
    this.keepDeviceAwake = false, // NEW
    this.memoryLimitMB = 100, // NEW: по умолчанию 100MB
    this.proxyOnlyMode = false, // NEW
    this.routeLanThroughProxy = false, // NEW
    this.tunnelMode = 'tun_proxy',
    this.blockUdp = false,
    this.showSpeedInNotification = false,
    this.connIdleTimeout = 300,
    this.maxTcpConns = 256,
    this.maxUdpConns = 128,
    this.excludedRoutes = kDefaultExcludedRoutes,
    this.logRetention = '24h',
    this.socksBindAddress = '127.0.0.1',
    this.socksPort = 10808,
    this.ipType = 'auto',
    this.pingMode = 'TCP',
    this.subAutoUpdate = false,
    this.subUpdateHours = 0,
    this.region = 'Россия (ru)',
    this.balancerStrategy = 'Round robin',
    this.blockAds = false,
    this.bypassLan = false,
    this.resolveDestination = false,
    this.ipv6Route = 'Отключить',
    List<RoutingRule>? routingRules,

    // DNS basic
    this.dnsRemote = 'tcp://8.8.8.8',
    this.dnsRemoteDomainStrategy = 'Авто',
    this.dnsFakeDns = false,
    this.dnsDirect = '1.1.1.1',
    this.dnsDirectDomainStrategy = 'Авто',

    // DNS server
    this.dnsTunHijackDns = true,
    this.dnsAllowIncomingDomains = false,
    this.dnsTestDomain = 'gstatic.com',
    this.dnsTtl = '12 h',
    this.dnsEnableRules = false,
    this.dnsDirectStreamEcs = true,
    this.dnsProxyResolveMode = 'FakeIP',

    // DNS override
    this.dnsPreferHttp3 = 'Не менять',
    this.dnsRespectRules = 'Не менять',
    this.dnsUseSystemDns = 'Не менять',
    this.dnsIpv6Override = 'Не менять',
    this.dnsUseHosts = 'Не менять',
    this.dnsEnhancedMode = 'Не менять',
    this.dnsNameserver = 'Не менять',
    this.dnsFallbackNameserver = 'Не менять',
    this.dnsDefaultNameserver = 'Не менять',
    this.dnsFakeIpFilter = 'Не менять',
    this.dnsFakeIpFilterMode = 'Не менять',
    this.dnsFallbackGeoip = 'Не менять',
    this.dnsFallbackGeoipCode = 'Не менять',
    this.dnsFallbackDomain = 'Не менять',
    this.dnsFallbackIpcidr = 'Не менять',
    this.dnsNameserverPolicy = 'Не менять',

    // Network
    this.netRouteSystemTraffic = true,
    this.netBypassPrivate = true,
    this.netHijackDns = true,
    this.netAllowBypass = true,
    this.netAllowIpv6 = false,
    this.netSystemProxy = true,

    // Local ports
    this.portHttp = 'Не менять',
    this.portSocks = 'Не менять',
    this.portRedir = 'Не менять',
    this.portTproxy = 'Не менять',
    this.portMixed = 'Не менять',
    this.portAuth = 'Не менять',
    this.portAllowLan = 'Не менять',
    this.portIpv6 = 'Не менять',
    this.portBindAddress = 'Не менять',

    // Proxy auth (NEW)
    this.socksAuthEnabled = false,
    this.socksAuthUsername = 'teleopen_user',
    this.socksAuthPassword = '',
    this.httpAuthEnabled = false,
    this.httpAuthUsername = 'teleopen_user',
    this.httpAuthPassword = '',

    // External Controller
    this.ecAddress = 'Не менять',
    this.ecAddressTls = 'Не менять',
    this.ecAllowOrigins = 'Не менять',
    this.ecAllowPrivateNetwork = 'Не менять',
    this.ecSecret = 'Не менять',
    this.ecMode = 'Не менять',
    this.ecLogLevel = 'Не менять',
    this.ecHosts = 'Не менять',

    // Meta
    this.metaUnifiedDelay = 'Не менять',
    this.metaGeoMode = 'Не менять',
    this.metaMptcp = 'Не менять',
    this.metaFindProcess = 'Не менять',
    this.metaStrategy = 'Не менять',
    this.metaSniffHttpPorts = 'Не менять',
    this.metaSniffHttpOverride = 'Не менять',
    this.metaSniffTlsPorts = 'Не менять',
    this.metaSniffTlsOverride = 'Не менять',
    this.metaSniffQuicPorts = 'Не менять',
    this.metaSniffQuicOverride = 'Не менять',
    this.metaForceDnsMapping = 'Не менять',
    this.metaParsePureIp = 'Не менять',
    this.metaOverrideDestination = 'Не менять',
    this.metaForceDomain = 'Не менять',
    this.metaSkipDomain = 'Не менять',
    this.metaSkipSrc = 'Не менять',
    this.metaSkipDst = 'Не менять',
    this.metaGeoipPath = '',
    this.metaGeositePath = '',
    this.metaCountryPath = '',
    this.metaAsnPath = '',

    // ByeDPI — прокси
    this.bdpiMaxConnections = '512',
    this.bdpiBufferSize = '16384',
    this.bdpiNoDomain = false,
    this.bdpiTcpFastOpen = false,
    // ByeDPI — десинхронизация
    this.bdpiHostsMode = 'Нет',
    this.bdpiDefaultTtl = '8',
    this.bdpiDesyncMethod = 'Disorder',
    this.bdpiSplitPosition = '1',
    this.bdpiSplitAtHost = false,
    this.bdpiDropSack = false,
    // ByeDPI — протоколы
    this.bdpiDesyncHttp = true,
    this.bdpiDesyncHttps = true,
    this.bdpiDesyncUdp = false,
    // ByeDPI — HTTP
    this.bdpiHostMixedCase = false,
    this.bdpiDomainMixedCase = false,
    this.bdpiHostRemoveSpaces = false,
    // ByeDPI — HTTPS
    this.bdpiTlsRecordSplit = false,
    this.bdpiTlsRecordSplitPos = '0',
    this.bdpiTlsRecordSplitAtSni = false,
    // ByeDPI — UDP
    this.bdpiFakeUdpCount = '0',
    // ByeDPI — стратегия / режим
    this.bdpiStrategy = '',
    this.bdpiModeEnabled = false,
  }) : routingRules = routingRules ?? [];

  /// Поверхностная копия — пригодится экранам, которым нужна локальная
  /// рабочая копия, не мутирующая глобальный AppState до явного save.
  AppSettings.copy(AppSettings o)
      : killSwitch = o.killSwitch,
        autoFailover = o.autoFailover,
        autoConnect = o.autoConnect,
        autoConnectOnBoot = o.autoConnectOnBoot, // NEW
        dns = o.dns,
        packetAnalysis = o.packetAnalysis,
        useMux = o.useMux,
        xrayTunMode = o.xrayTunMode, // NEW
        keepDeviceAwake = o.keepDeviceAwake, // NEW
        memoryLimitMB = o.memoryLimitMB, // NEW
        proxyOnlyMode = o.proxyOnlyMode, // NEW
        routeLanThroughProxy = o.routeLanThroughProxy, // NEW
        tunnelMode = o.tunnelMode,
        blockUdp = o.blockUdp,
        showSpeedInNotification = o.showSpeedInNotification,
        connIdleTimeout = o.connIdleTimeout,
        maxTcpConns = o.maxTcpConns,
        maxUdpConns = o.maxUdpConns,
        excludedRoutes = List<String>.from(o.excludedRoutes),
        logRetention = o.logRetention,
        socksBindAddress = o.socksBindAddress,
        socksPort = o.socksPort,
        ipType = o.ipType,
        pingMode = o.pingMode,
        subAutoUpdate = o.subAutoUpdate,
        subUpdateHours = o.subUpdateHours,
        region = o.region,
        balancerStrategy = o.balancerStrategy,
        blockAds = o.blockAds,
        bypassLan = o.bypassLan,
        resolveDestination = o.resolveDestination,
        ipv6Route = o.ipv6Route,
        routingRules = o.routingRules.map((r) => r.copy()).toList(),
        dnsRemote = o.dnsRemote,
        dnsRemoteDomainStrategy = o.dnsRemoteDomainStrategy,
        dnsFakeDns = o.dnsFakeDns,
        dnsDirect = o.dnsDirect,
        dnsDirectDomainStrategy = o.dnsDirectDomainStrategy,
        dnsTunHijackDns = o.dnsTunHijackDns,
        dnsAllowIncomingDomains = o.dnsAllowIncomingDomains,
        dnsTestDomain = o.dnsTestDomain,
        dnsTtl = o.dnsTtl,
        dnsEnableRules = o.dnsEnableRules,
        dnsDirectStreamEcs = o.dnsDirectStreamEcs,
        dnsProxyResolveMode = o.dnsProxyResolveMode,
        dnsPreferHttp3 = o.dnsPreferHttp3,
        dnsRespectRules = o.dnsRespectRules,
        dnsUseSystemDns = o.dnsUseSystemDns,
        dnsIpv6Override = o.dnsIpv6Override,
        dnsUseHosts = o.dnsUseHosts,
        dnsEnhancedMode = o.dnsEnhancedMode,
        dnsNameserver = o.dnsNameserver,
        dnsFallbackNameserver = o.dnsFallbackNameserver,
        dnsDefaultNameserver = o.dnsDefaultNameserver,
        dnsFakeIpFilter = o.dnsFakeIpFilter,
        dnsFakeIpFilterMode = o.dnsFakeIpFilterMode,
        dnsFallbackGeoip = o.dnsFallbackGeoip,
        dnsFallbackGeoipCode = o.dnsFallbackGeoipCode,
        dnsFallbackDomain = o.dnsFallbackDomain,
        dnsFallbackIpcidr = o.dnsFallbackIpcidr,
        dnsNameserverPolicy = o.dnsNameserverPolicy,
        netRouteSystemTraffic = o.netRouteSystemTraffic,
        netBypassPrivate = o.netBypassPrivate,
        netHijackDns = o.netHijackDns,
        netAllowBypass = o.netAllowBypass,
        netAllowIpv6 = o.netAllowIpv6,
        netSystemProxy = o.netSystemProxy,
        portHttp = o.portHttp,
        portSocks = o.portSocks,
        portRedir = o.portRedir,
        portTproxy = o.portTproxy,
        portMixed = o.portMixed,
        portAuth = o.portAuth,
        portAllowLan = o.portAllowLan,
        portIpv6 = o.portIpv6,
        portBindAddress = o.portBindAddress,
        socksAuthEnabled = o.socksAuthEnabled, // NEW
        socksAuthUsername = o.socksAuthUsername, // NEW
        socksAuthPassword = o.socksAuthPassword, // NEW
        httpAuthEnabled = o.httpAuthEnabled, // NEW
        httpAuthUsername = o.httpAuthUsername, // NEW
        httpAuthPassword = o.httpAuthPassword, // NEW
        ecAddress = o.ecAddress,
        ecAddressTls = o.ecAddressTls,
        ecAllowOrigins = o.ecAllowOrigins,
        ecAllowPrivateNetwork = o.ecAllowPrivateNetwork,
        ecSecret = o.ecSecret,
        ecMode = o.ecMode,
        ecLogLevel = o.ecLogLevel,
        ecHosts = o.ecHosts,
        metaUnifiedDelay = o.metaUnifiedDelay,
        metaGeoMode = o.metaGeoMode,
        metaMptcp = o.metaMptcp,
        metaFindProcess = o.metaFindProcess,
        metaStrategy = o.metaStrategy,
        metaSniffHttpPorts = o.metaSniffHttpPorts,
        metaSniffHttpOverride = o.metaSniffHttpOverride,
        metaSniffTlsPorts = o.metaSniffTlsPorts,
        metaSniffTlsOverride = o.metaSniffTlsOverride,
        metaSniffQuicPorts = o.metaSniffQuicPorts,
        metaSniffQuicOverride = o.metaSniffQuicOverride,
        metaForceDnsMapping = o.metaForceDnsMapping,
        metaParsePureIp = o.metaParsePureIp,
        metaOverrideDestination = o.metaOverrideDestination,
        metaForceDomain = o.metaForceDomain,
        metaSkipDomain = o.metaSkipDomain,
        metaSkipSrc = o.metaSkipSrc,
        metaSkipDst = o.metaSkipDst,
        metaGeoipPath = o.metaGeoipPath,
        metaGeositePath = o.metaGeositePath,
        metaCountryPath = o.metaCountryPath,
        metaAsnPath = o.metaAsnPath,
        bdpiMaxConnections = o.bdpiMaxConnections,
        bdpiBufferSize = o.bdpiBufferSize,
        bdpiNoDomain = o.bdpiNoDomain,
        bdpiTcpFastOpen = o.bdpiTcpFastOpen,
        bdpiHostsMode = o.bdpiHostsMode,
        bdpiDefaultTtl = o.bdpiDefaultTtl,
        bdpiDesyncMethod = o.bdpiDesyncMethod,
        bdpiSplitPosition = o.bdpiSplitPosition,
        bdpiSplitAtHost = o.bdpiSplitAtHost,
        bdpiDropSack = o.bdpiDropSack,
        bdpiDesyncHttp = o.bdpiDesyncHttp,
        bdpiDesyncHttps = o.bdpiDesyncHttps,
        bdpiDesyncUdp = o.bdpiDesyncUdp,
        bdpiHostMixedCase = o.bdpiHostMixedCase,
        bdpiDomainMixedCase = o.bdpiDomainMixedCase,
        bdpiHostRemoveSpaces = o.bdpiHostRemoveSpaces,
        bdpiTlsRecordSplit = o.bdpiTlsRecordSplit,
        bdpiTlsRecordSplitPos = o.bdpiTlsRecordSplitPos,
        bdpiTlsRecordSplitAtSni = o.bdpiTlsRecordSplitAtSni,
        bdpiFakeUdpCount = o.bdpiFakeUdpCount,
        bdpiStrategy = o.bdpiStrategy,
        bdpiModeEnabled = o.bdpiModeEnabled;

  static AppSettings fromPrefs(SharedPreferences p) => AppSettings(
        killSwitch: p.getBool('s_killSwitch') ?? false,
        autoConnect: p.getBool('s_autoConnect') ?? false,
        autoConnectOnBoot: p.getBool('s_autoConnectOnBoot') ?? false, // NEW
        autoFailover: p.getBool('s_autoFailover') ?? false,
        dns: p.getString('s_dns') ?? '1.1.1.1',
        packetAnalysis: p.getBool('s_packetAnalysis') ?? true,
        useMux: p.getBool('s_useMux') ?? false,
        xrayTunMode: p.getBool('s_xrayTunMode') ?? false, // NEW
        keepDeviceAwake: p.getBool('s_keepDeviceAwake') ?? false, // NEW
        memoryLimitMB: p.getInt('s_memoryLimitMB') ?? 100, // NEW
        proxyOnlyMode: p.getBool('s_proxyOnlyMode') ?? false, // NEW
        routeLanThroughProxy: p.getBool('s_routeLanThroughProxy') ?? false, // NEW
        tunnelMode: p.getString('s_tunnelMode') ?? 'tun_proxy',
        blockUdp: p.getBool('s_blockUdp') ?? false,
        showSpeedInNotification: p.getBool('s_showSpeedInNotification') ?? false,
        connIdleTimeout: p.getInt('s_connIdleTimeout') ?? 300,
        maxTcpConns: p.getInt('s_maxTcpConns') ?? 256,
        maxUdpConns: p.getInt('s_maxUdpConns') ?? 128,
        excludedRoutes:
            p.getStringList('s_excludedRoutes') ?? List<String>.from(kDefaultExcludedRoutes),
        logRetention: p.getString('s_logRetention') ?? '24h',
        socksBindAddress: p.getString('s_socksBindAddress') ?? '127.0.0.1',
        socksPort: p.getInt('s_socksPort') ?? 10808,
        ipType: p.getString('s_ipType') ?? 'auto',
        pingMode: p.getString('s_pingMode') ?? 'TCP',
        subAutoUpdate: p.getBool('s_subAutoUpdate') ?? false,
        subUpdateHours: p.getInt('s_subUpdateHours') ?? 0,
        region: p.getString('s_region') ?? 'Россия (ru)',
        balancerStrategy: p.getString('s_balancerStrategy') ?? 'Round robin',
        blockAds: p.getBool('s_blockAds') ?? false,
        bypassLan: p.getBool('s_bypassLan') ?? false,
        resolveDestination: p.getBool('s_resolveDestination') ?? false,
        ipv6Route: p.getString('s_ipv6Route') ?? 'Отключить',
        routingRules: _decodeRules(p.getString('s_routingRules')),

        // DNS basic
        dnsRemote: p.getString('s_dnsRemote') ?? 'tcp://8.8.8.8',
        dnsRemoteDomainStrategy:
            p.getString('s_dnsRemoteDomainStrategy') ?? 'Авто',
        dnsFakeDns: p.getBool('s_dnsFakeDns') ?? false,
        dnsDirect: p.getString('s_dnsDirect') ?? '1.1.1.1',
        dnsDirectDomainStrategy:
            p.getString('s_dnsDirectDomainStrategy') ?? 'Авто',

        // DNS server
        dnsTunHijackDns: p.getBool('s_dnsTunHijackDns') ?? true,
        dnsAllowIncomingDomains:
            p.getBool('s_dnsAllowIncomingDomains') ?? false,
        dnsTestDomain: p.getString('s_dnsTestDomain') ?? 'gstatic.com',
        dnsTtl: p.getString('s_dnsTtl') ?? '12 h',
        dnsEnableRules: p.getBool('s_dnsEnableRules') ?? false,
        dnsDirectStreamEcs: p.getBool('s_dnsDirectStreamEcs') ?? true,
        dnsProxyResolveMode: p.getString('s_dnsProxyResolveMode') ?? 'FakeIP',

        // DNS override
        dnsPreferHttp3: p.getString('s_dnsPreferHttp3') ?? 'Не менять',
        dnsRespectRules: p.getString('s_dnsRespectRules') ?? 'Не менять',
        dnsUseSystemDns: p.getString('s_dnsUseSystemDns') ?? 'Не менять',
        dnsIpv6Override: p.getString('s_dnsIpv6Override') ?? 'Не менять',
        dnsUseHosts: p.getString('s_dnsUseHosts') ?? 'Не менять',
        dnsEnhancedMode: p.getString('s_dnsEnhancedMode') ?? 'Не менять',
        dnsNameserver: p.getString('s_dnsNameserver') ?? 'Не менять',
        dnsFallbackNameserver:
            p.getString('s_dnsFallbackNameserver') ?? 'Не менять',
        dnsDefaultNameserver:
            p.getString('s_dnsDefaultNameserver') ?? 'Не менять',
        dnsFakeIpFilter: p.getString('s_dnsFakeIpFilter') ?? 'Не менять',
        dnsFakeIpFilterMode:
            p.getString('s_dnsFakeIpFilterMode') ?? 'Не менять',
        dnsFallbackGeoip: p.getString('s_dnsFallbackGeoip') ?? 'Не менять',
        dnsFallbackGeoipCode:
            p.getString('s_dnsFallbackGeoipCode') ?? 'Не менять',
        dnsFallbackDomain: p.getString('s_dnsFallbackDomain') ?? 'Не менять',
        dnsFallbackIpcidr: p.getString('s_dnsFallbackIpcidr') ?? 'Не менять',
        dnsNameserverPolicy:
            p.getString('s_dnsNameserverPolicy') ?? 'Не менять',

        // Network
        netRouteSystemTraffic: p.getBool('s_netRouteSystemTraffic') ?? true,
        netBypassPrivate: p.getBool('s_netBypassPrivate') ?? true,
        netHijackDns: p.getBool('s_netHijackDns') ?? true,
        netAllowBypass: p.getBool('s_netAllowBypass') ?? true,
        netAllowIpv6: p.getBool('s_netAllowIpv6') ?? false,
        netSystemProxy: p.getBool('s_netSystemProxy') ?? true,

        // Local ports
        portHttp: p.getString('s_portHttp') ?? 'Не менять',
        portSocks: p.getString('s_portSocks') ?? 'Не менять',
        portRedir: p.getString('s_portRedir') ?? 'Не менять',
        portTproxy: p.getString('s_portTproxy') ?? 'Не менять',
        portMixed: p.getString('s_portMixed') ?? 'Не менять',
        // HIGH-5: portAuth (логин:пароль прокси) хранится в зашифрованном
        // хранилище, а не в prefs. Здесь дефолт-сентинел; реальное значение
        // подтянет AppState._loadSecureSettings().
        portAuth: 'Не менять',
        portAllowLan: p.getString('s_portAllowLan') ?? 'Не менять',
        portIpv6: p.getString('s_portIpv6') ?? 'Не менять',
        portBindAddress: p.getString('s_portBindAddress') ?? 'Не менять',

        // Proxy auth (NEW) - храним в prefs, но пароли можно позже в secure store
        socksAuthEnabled: p.getBool('s_socksAuthEnabled') ?? false,
        socksAuthUsername: p.getString('s_socksAuthUsername') ?? 'teleopen_user',
        socksAuthPassword: p.getString('s_socksAuthPassword') ?? '',
        httpAuthEnabled: p.getBool('s_httpAuthEnabled') ?? false,
        httpAuthUsername: p.getString('s_httpAuthUsername') ?? 'teleopen_user',
        httpAuthPassword: p.getString('s_httpAuthPassword') ?? '',

        // External Controller
        ecAddress: p.getString('s_ecAddress') ?? 'Не менять',
        ecAddressTls: p.getString('s_ecAddressTls') ?? 'Не менять',
        ecAllowOrigins: p.getString('s_ecAllowOrigins') ?? 'Не менять',
        ecAllowPrivateNetwork:
            p.getString('s_ecAllowPrivateNetwork') ?? 'Не менять',
        // HIGH-5: ecSecret в зашифрованном хранилище (см. portAuth выше).
        ecSecret: 'Не менять',
        ecMode: p.getString('s_ecMode') ?? 'Не менять',
        ecLogLevel: p.getString('s_ecLogLevel') ?? 'Не менять',
        ecHosts: p.getString('s_ecHosts') ?? 'Не менять',

        // Meta
        metaUnifiedDelay: p.getString('s_metaUnifiedDelay') ?? 'Не менять',
        metaGeoMode: p.getString('s_metaGeoMode') ?? 'Не менять',
        metaMptcp: p.getString('s_metaMptcp') ?? 'Не менять',
        metaFindProcess: p.getString('s_metaFindProcess') ?? 'Не менять',
        metaStrategy: p.getString('s_metaStrategy') ?? 'Не менять',
        metaSniffHttpPorts: p.getString('s_metaSniffHttpPorts') ?? 'Не менять',
        metaSniffHttpOverride:
            p.getString('s_metaSniffHttpOverride') ?? 'Не менять',
        metaSniffTlsPorts: p.getString('s_metaSniffTlsPorts') ?? 'Не менять',
        metaSniffTlsOverride:
            p.getString('s_metaSniffTlsOverride') ?? 'Не менять',
        metaSniffQuicPorts: p.getString('s_metaSniffQuicPorts') ?? 'Не менять',
        metaSniffQuicOverride:
            p.getString('s_metaSniffQuicOverride') ?? 'Не менять',
        metaForceDnsMapping:
            p.getString('s_metaForceDnsMapping') ?? 'Не менять',
        metaParsePureIp: p.getString('s_metaParsePureIp') ?? 'Не менять',
        metaOverrideDestination:
            p.getString('s_metaOverrideDestination') ?? 'Не менять',
        metaForceDomain: p.getString('s_metaForceDomain') ?? 'Не менять',
        metaSkipDomain: p.getString('s_metaSkipDomain') ?? 'Не менять',
        metaSkipSrc: p.getString('s_metaSkipSrc') ?? 'Не менять',
        metaSkipDst: p.getString('s_metaSkipDst') ?? 'Не менять',
        metaGeoipPath: p.getString('s_metaGeoipPath') ?? '',
        metaGeositePath: p.getString('s_metaGeositePath') ?? '',
        metaCountryPath: p.getString('s_metaCountryPath') ?? '',
        metaAsnPath: p.getString('s_metaAsnPath') ?? '',

        // ByeDPI
        bdpiMaxConnections: p.getString('s_bdpiMaxConnections') ?? '512',
        bdpiBufferSize: p.getString('s_bdpiBufferSize') ?? '16384',
        bdpiNoDomain: p.getBool('s_bdpiNoDomain') ?? false,
        bdpiTcpFastOpen: p.getBool('s_bdpiTcpFastOpen') ?? false,
        bdpiHostsMode: p.getString('s_bdpiHostsMode') ?? 'Нет',
        bdpiDefaultTtl: p.getString('s_bdpiDefaultTtl') ?? '8',
        bdpiDesyncMethod: p.getString('s_bdpiDesyncMethod') ?? 'Disorder',
        bdpiSplitPosition: p.getString('s_bdpiSplitPosition') ?? '1',
        bdpiSplitAtHost: p.getBool('s_bdpiSplitAtHost') ?? false,
        bdpiDropSack: p.getBool('s_bdpiDropSack') ?? false,
        bdpiDesyncHttp: p.getBool('s_bdpiDesyncHttp') ?? true,
        bdpiDesyncHttps: p.getBool('s_bdpiDesyncHttps') ?? true,
        bdpiDesyncUdp: p.getBool('s_bdpiDesyncUdp') ?? false,
        bdpiHostMixedCase: p.getBool('s_bdpiHostMixedCase') ?? false,
        bdpiDomainMixedCase: p.getBool('s_bdpiDomainMixedCase') ?? false,
        bdpiHostRemoveSpaces: p.getBool('s_bdpiHostRemoveSpaces') ?? false,
        bdpiTlsRecordSplit: p.getBool('s_bdpiTlsRecordSplit') ?? false,
        bdpiTlsRecordSplitPos: p.getString('s_bdpiTlsRecordSplitPos') ?? '0',
        bdpiTlsRecordSplitAtSni:
            p.getBool('s_bdpiTlsRecordSplitAtSni') ?? false,
        bdpiFakeUdpCount: p.getString('s_bdpiFakeUdpCount') ?? '0',
        bdpiStrategy: p.getString('s_bdpiStrategy') ?? '',
        bdpiModeEnabled: p.getBool('s_bdpiModeEnabled') ?? false,
      );

  void save(SharedPreferences p) {
    p.setBool('s_killSwitch', killSwitch);
    p.setBool('s_autoConnect', autoConnect);
    p.setBool('s_autoConnectOnBoot', autoConnectOnBoot); // NEW
    p.setBool('s_autoFailover', autoFailover);
    p.setString('s_dns', dns);
    p.setBool('s_packetAnalysis', packetAnalysis);
    p.setBool('s_useMux', useMux);
    p.setBool('s_xrayTunMode', xrayTunMode); // NEW
    p.setBool('s_keepDeviceAwake', keepDeviceAwake); // NEW
    p.setInt('s_memoryLimitMB', memoryLimitMB); // NEW
    p.setBool('s_proxyOnlyMode', proxyOnlyMode); // NEW
    p.setBool('s_routeLanThroughProxy', routeLanThroughProxy); // NEW
    p.setString('s_tunnelMode', tunnelMode);
    p.setBool('s_blockUdp', blockUdp);
    p.setBool('s_showSpeedInNotification', showSpeedInNotification);
    p.setInt('s_connIdleTimeout', connIdleTimeout);
    p.setInt('s_maxTcpConns', maxTcpConns);
    p.setInt('s_maxUdpConns', maxUdpConns);
    p.setStringList('s_excludedRoutes', excludedRoutes);
    p.setString('s_logRetention', logRetention);
    p.setString('s_socksBindAddress', socksBindAddress);
    p.setInt('s_socksPort', socksPort);
    p.setString('s_ipType', ipType);
    p.setString('s_pingMode', pingMode);
    p.setBool('s_subAutoUpdate', subAutoUpdate);
    p.setInt('s_subUpdateHours', subUpdateHours);
    p.setString('s_region', region);
    p.setString('s_balancerStrategy', balancerStrategy);
    p.setBool('s_blockAds', blockAds);
    p.setBool('s_bypassLan', bypassLan);
    p.setBool('s_resolveDestination', resolveDestination);
    p.setString('s_ipv6Route', ipv6Route);
    p.setString('s_routingRules',
        jsonEncode(routingRules.map((r) => r.toJson()).toList()));

    // DNS basic
    p.setString('s_dnsRemote', dnsRemote);
    p.setString('s_dnsRemoteDomainStrategy', dnsRemoteDomainStrategy);
    p.setBool('s_dnsFakeDns', dnsFakeDns);
    p.setString('s_dnsDirect', dnsDirect);
    p.setString('s_dnsDirectDomainStrategy', dnsDirectDomainStrategy);

    // DNS server
    p.setBool('s_dnsTunHijackDns', dnsTunHijackDns);
    p.setBool('s_dnsAllowIncomingDomains', dnsAllowIncomingDomains);
    p.setString('s_dnsTestDomain', dnsTestDomain);
    p.setString('s_dnsTtl', dnsTtl);
    p.setBool('s_dnsEnableRules', dnsEnableRules);
    p.setBool('s_dnsDirectStreamEcs', dnsDirectStreamEcs);
    p.setString('s_dnsProxyResolveMode', dnsProxyResolveMode);

    // DNS override
    p.setString('s_dnsPreferHttp3', dnsPreferHttp3);
    p.setString('s_dnsRespectRules', dnsRespectRules);
    p.setString('s_dnsUseSystemDns', dnsUseSystemDns);
    p.setString('s_dnsIpv6Override', dnsIpv6Override);
    p.setString('s_dnsUseHosts', dnsUseHosts);
    p.setString('s_dnsEnhancedMode', dnsEnhancedMode);
    p.setString('s_dnsNameserver', dnsNameserver);
    p.setString('s_dnsFallbackNameserver', dnsFallbackNameserver);
    p.setString('s_dnsDefaultNameserver', dnsDefaultNameserver);
    p.setString('s_dnsFakeIpFilter', dnsFakeIpFilter);
    p.setString('s_dnsFakeIpFilterMode', dnsFakeIpFilterMode);
    p.setString('s_dnsFallbackGeoip', dnsFallbackGeoip);
    p.setString('s_dnsFallbackGeoipCode', dnsFallbackGeoipCode);
    p.setString('s_dnsFallbackDomain', dnsFallbackDomain);
    p.setString('s_dnsFallbackIpcidr', dnsFallbackIpcidr);
    p.setString('s_dnsNameserverPolicy', dnsNameserverPolicy);

    // Network
    p.setBool('s_netRouteSystemTraffic', netRouteSystemTraffic);
    p.setBool('s_netBypassPrivate', netBypassPrivate);
    p.setBool('s_netHijackDns', netHijackDns);
    p.setBool('s_netAllowBypass', netAllowBypass);
    p.setBool('s_netAllowIpv6', netAllowIpv6);
    p.setBool('s_netSystemProxy', netSystemProxy);

    // Local ports
    p.setString('s_portHttp', portHttp);
    p.setString('s_portSocks', portSocks);
    p.setString('s_portRedir', portRedir);
    p.setString('s_portTproxy', portTproxy);
    p.setString('s_portMixed', portMixed);
    // HIGH-5: s_portAuth НЕ пишем в prefs — секрет уходит в SecureStore
    // (см. AppState.updateSettings / _loadSecureSettings).
    p.setString('s_portAllowLan', portAllowLan);
    p.setString('s_portIpv6', portIpv6);
    p.setString('s_portBindAddress', portBindAddress);

    // Proxy auth (NEW)
    p.setBool('s_socksAuthEnabled', socksAuthEnabled);
    p.setString('s_socksAuthUsername', socksAuthUsername);
    p.setString('s_socksAuthPassword', socksAuthPassword);
    p.setBool('s_httpAuthEnabled', httpAuthEnabled);
    p.setString('s_httpAuthUsername', httpAuthUsername);
    p.setString('s_httpAuthPassword', httpAuthPassword);

    // External Controller
    p.setString('s_ecAddress', ecAddress);
    p.setString('s_ecAddressTls', ecAddressTls);
    p.setString('s_ecAllowOrigins', ecAllowOrigins);
    p.setString('s_ecAllowPrivateNetwork', ecAllowPrivateNetwork);
    // HIGH-5: s_ecSecret НЕ пишем в prefs — секрет уходит в SecureStore.
    p.setString('s_ecMode', ecMode);
    p.setString('s_ecLogLevel', ecLogLevel);
    p.setString('s_ecHosts', ecHosts);

    // Meta
    p.setString('s_metaUnifiedDelay', metaUnifiedDelay);
    p.setString('s_metaGeoMode', metaGeoMode);
    p.setString('s_metaMptcp', metaMptcp);
    p.setString('s_metaFindProcess', metaFindProcess);
    p.setString('s_metaStrategy', metaStrategy);
    p.setString('s_metaSniffHttpPorts', metaSniffHttpPorts);
    p.setString('s_metaSniffHttpOverride', metaSniffHttpOverride);
    p.setString('s_metaSniffTlsPorts', metaSniffTlsPorts);
    p.setString('s_metaSniffTlsOverride', metaSniffTlsOverride);
    p.setString('s_metaSniffQuicPorts', metaSniffQuicPorts);
    p.setString('s_metaSniffQuicOverride', metaSniffQuicOverride);
    p.setString('s_metaForceDnsMapping', metaForceDnsMapping);
    p.setString('s_metaParsePureIp', metaParsePureIp);
    p.setString('s_metaOverrideDestination', metaOverrideDestination);
    p.setString('s_metaForceDomain', metaForceDomain);
    p.setString('s_metaSkipDomain', metaSkipDomain);
    p.setString('s_metaSkipSrc', metaSkipSrc);
    p.setString('s_metaSkipDst', metaSkipDst);
    p.setString('s_metaGeoipPath', metaGeoipPath);
    p.setString('s_metaGeositePath', metaGeositePath);
    p.setString('s_metaCountryPath', metaCountryPath);
    p.setString('s_metaAsnPath', metaAsnPath);

    // ByeDPI
    p.setString('s_bdpiMaxConnections', bdpiMaxConnections);
    p.setString('s_bdpiBufferSize', bdpiBufferSize);
    p.setBool('s_bdpiNoDomain', bdpiNoDomain);
    p.setBool('s_bdpiTcpFastOpen', bdpiTcpFastOpen);
    p.setString('s_bdpiHostsMode', bdpiHostsMode);
    p.setString('s_bdpiDefaultTtl', bdpiDefaultTtl);
    p.setString('s_bdpiDesyncMethod', bdpiDesyncMethod);
    p.setString('s_bdpiSplitPosition', bdpiSplitPosition);
    p.setBool('s_bdpiSplitAtHost', bdpiSplitAtHost);
    p.setBool('s_bdpiDropSack', bdpiDropSack);
    p.setBool('s_bdpiDesyncHttp', bdpiDesyncHttp);
    p.setBool('s_bdpiDesyncHttps', bdpiDesyncHttps);
    p.setBool('s_bdpiDesyncUdp', bdpiDesyncUdp);
    p.setBool('s_bdpiHostMixedCase', bdpiHostMixedCase);
    p.setBool('s_bdpiDomainMixedCase', bdpiDomainMixedCase);
    p.setBool('s_bdpiHostRemoveSpaces', bdpiHostRemoveSpaces);
    p.setBool('s_bdpiTlsRecordSplit', bdpiTlsRecordSplit);
    p.setString('s_bdpiTlsRecordSplitPos', bdpiTlsRecordSplitPos);
    p.setBool('s_bdpiTlsRecordSplitAtSni', bdpiTlsRecordSplitAtSni);
    p.setString('s_bdpiFakeUdpCount', bdpiFakeUdpCount);
    p.setString('s_bdpiStrategy', bdpiStrategy);
    p.setBool('s_bdpiModeEnabled', bdpiModeEnabled);
  }

  /// Декодирует список правил маршрутизации из JSON-строки prefs.
  static List<RoutingRule> _decodeRules(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => RoutingRule.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Извлекает двухбуквенный код страны из строки региона вида "Россия (ru)".
  /// Возвращает код в нижнем регистре ('ru') или '' если не удалось распарсить.
  static String regionCodeOf(String region) {
    final m = RegExp(r'\(([A-Za-z]{2})\)').firstMatch(region);
    return m == null ? '' : m.group(1)!.toLowerCase();
  }

  /// Сериализация в Map для отправки в нативный слой (mihomo/clash.meta).
  /// 'Не менять' / пустые строки в финальный конфиг не попадают.
  Map<String, dynamic> toCoreConfig() {
    final m = <String, dynamic>{};

    void putStr(String key, String v) {
      if (v.isNotEmpty && v != 'Не менять') m[key] = v;
    }

    // base
    m['kill_switch'] = killSwitch;
    m['auto_connect'] = autoConnect;
    m['auto_failover'] = autoFailover;
    m['dns_system'] = dns;
    m['packet_analysis'] = packetAnalysis;
    m['use_mux'] = useMux;
    m['region'] = region;
    // Двухбуквенный код страны из region (формат "Россия (ru)") — натив
    // строит из него geoip-правило. Пусто = правило не добавляется.
    m['region_code'] = regionCodeOf(region);
    m['balancer_strategy'] = balancerStrategy;
    m['block_ads'] = blockAds;
    m['bypass_lan'] = bypassLan;
    m['resolve_destination'] = resolveDestination;
    m['ipv6_route'] = ipv6Route;
    // Пользовательские правила маршрутизации (geosite/geoip/домен/IP → действие).
    // Натив (ensureTunInbound) разворачивает их в field-правила xray. Только
    // включённые и непустые; порядок = приоритет.
    m['routing_rules'] = [
      for (final r in routingRules)
        if (r.enabled && r.value.trim().isNotEmpty)
          {'kind': r.kind.id, 'value': r.value.trim(), 'action': r.action.id},
    ];

    // DNS basic
    m['dns_remote'] = dnsRemote;
    m['dns_remote_strategy'] = dnsRemoteDomainStrategy;
    m['dns_fake'] = dnsFakeDns;
    m['dns_direct'] = dnsDirect;
    m['dns_direct_strategy'] = dnsDirectDomainStrategy;

    // DNS server
    m['dns_tun_hijack'] = dnsTunHijackDns;
    m['dns_allow_incoming_domains'] = dnsAllowIncomingDomains;
    m['dns_test_domain'] = dnsTestDomain;
    m['dns_ttl'] = dnsTtl;
    m['dns_enable_rules'] = dnsEnableRules;
    m['dns_direct_ecs'] = dnsDirectStreamEcs;
    m['dns_proxy_resolve_mode'] = dnsProxyResolveMode;

    // DNS overrides (отправляем только не-сентинелы)
    putStr('dns_prefer_http3', dnsPreferHttp3);
    putStr('dns_respect_rules', dnsRespectRules);
    putStr('dns_use_system', dnsUseSystemDns);
    putStr('dns_ipv6', dnsIpv6Override);
    putStr('dns_use_hosts', dnsUseHosts);
    putStr('dns_enhanced_mode', dnsEnhancedMode);
    putStr('dns_nameserver', dnsNameserver);
    putStr('dns_fallback_nameserver', dnsFallbackNameserver);
    putStr('dns_default_nameserver', dnsDefaultNameserver);
    putStr('dns_fake_ip_filter', dnsFakeIpFilter);
    putStr('dns_fake_ip_filter_mode', dnsFakeIpFilterMode);
    putStr('dns_fallback_geoip', dnsFallbackGeoip);
    putStr('dns_fallback_geoip_code', dnsFallbackGeoipCode);
    putStr('dns_fallback_domain', dnsFallbackDomain);
    putStr('dns_fallback_ipcidr', dnsFallbackIpcidr);
    putStr('dns_nameserver_policy', dnsNameserverPolicy);

    // Network
    // ВАЖНО: главный экран настроек дублирует «Обход LAN» (bypassLan) и «Маршрут
    // IPv6» (ipv6Route), но писал их в ключи bypass_lan/ipv6_route, которые натив
    // не читает. Реально нативка (HysteriaTunVpnService) читает net_bypass_private
    // и net_allow_ipv6. Поэтому ИЛИ-объединяем оба источника — тумблер с любого
    // экрана даёт эффект.
    m['net_route_system'] = netRouteSystemTraffic;
    m['net_bypass_private'] = netBypassPrivate || bypassLan;
    m['net_hijack_dns'] = netHijackDns;
    m['net_allow_bypass'] = netAllowBypass;
    m['net_allow_ipv6'] = netAllowIpv6 || (ipv6Route != 'Отключить');
    m['net_system_proxy'] = netSystemProxy;

    // ── INCY round 2: новые нативные настройки ────────────────────────────
    m['tunnel_mode'] = tunnelMode; // tun_proxy | tun_only | proxy_only
    m['block_udp'] = blockUdp;
    m['show_speed_notification'] = showSpeedInNotification;
    m['conn_idle_timeout'] = connIdleTimeout;
    m['max_tcp_conns'] = maxTcpConns;
    m['max_udp_conns'] = maxUdpConns;
    m['excluded_routes'] = excludedRoutes; // JSON-массив CIDR (native читает напрямую)
    m['log_retention'] = logRetention;
    m['socks_bind_address'] = socksBindAddress;
    m['socks_port'] = socksPort;
    m['ip_type'] = ipType; // ipv4 | ipv6 | auto

    // Local ports
    putStr('port_http', portHttp);
    putStr('port_socks', portSocks);
    putStr('port_redir', portRedir);
    putStr('port_tproxy', portTproxy);
    putStr('port_mixed', portMixed);
    putStr('port_auth', portAuth);
    putStr('port_allow_lan', portAllowLan);
    putStr('port_ipv6', portIpv6);
    putStr('port_bind_address', portBindAddress);

    // External Controller
    putStr('ec_address', ecAddress);
    putStr('ec_address_tls', ecAddressTls);
    putStr('ec_allow_origins', ecAllowOrigins);
    putStr('ec_allow_private', ecAllowPrivateNetwork);
    putStr('ec_secret', ecSecret);
    putStr('ec_mode', ecMode);
    putStr('ec_log_level', ecLogLevel);
    putStr('ec_hosts', ecHosts);

    // Meta
    putStr('meta_unified_delay', metaUnifiedDelay);
    putStr('meta_geo_mode', metaGeoMode);
    putStr('meta_mptcp', metaMptcp);
    putStr('meta_find_process', metaFindProcess);
    putStr('meta_strategy', metaStrategy);
    putStr('meta_sniff_http_ports', metaSniffHttpPorts);
    putStr('meta_sniff_http_override', metaSniffHttpOverride);
    putStr('meta_sniff_tls_ports', metaSniffTlsPorts);
    putStr('meta_sniff_tls_override', metaSniffTlsOverride);
    putStr('meta_sniff_quic_ports', metaSniffQuicPorts);
    putStr('meta_sniff_quic_override', metaSniffQuicOverride);
    putStr('meta_force_dns_mapping', metaForceDnsMapping);
    putStr('meta_parse_pure_ip', metaParsePureIp);
    putStr('meta_override_destination', metaOverrideDestination);
    putStr('meta_force_domain', metaForceDomain);
    putStr('meta_skip_domain', metaSkipDomain);
    putStr('meta_skip_src', metaSkipSrc);
    putStr('meta_skip_dst', metaSkipDst);
    if (metaGeoipPath.isNotEmpty) m['meta_geoip_path'] = metaGeoipPath;
    if (metaGeositePath.isNotEmpty) m['meta_geosite_path'] = metaGeositePath;
    if (metaCountryPath.isNotEmpty) m['meta_country_path'] = metaCountryPath;
    if (metaAsnPath.isNotEmpty) m['meta_asn_path'] = metaAsnPath;

    // ByeDPI (обход DPI). Передаём как есть; нативный движок ByeDPI применит
    // их, когда будет подключён. Числовые поля идут строками — нативка парсит.
    m['bdpi_max_connections'] = bdpiMaxConnections;
    m['bdpi_buffer_size'] = bdpiBufferSize;
    m['bdpi_no_domain'] = bdpiNoDomain;
    m['bdpi_tcp_fast_open'] = bdpiTcpFastOpen;
    m['bdpi_hosts_mode'] = bdpiHostsMode;
    m['bdpi_default_ttl'] = bdpiDefaultTtl;
    m['bdpi_desync_method'] = bdpiDesyncMethod;
    m['bdpi_split_position'] = bdpiSplitPosition;
    m['bdpi_split_at_host'] = bdpiSplitAtHost;
    m['bdpi_drop_sack'] = bdpiDropSack;
    m['bdpi_desync_http'] = bdpiDesyncHttp;
    m['bdpi_desync_https'] = bdpiDesyncHttps;
    m['bdpi_desync_udp'] = bdpiDesyncUdp;
    m['bdpi_host_mixed_case'] = bdpiHostMixedCase;
    m['bdpi_domain_mixed_case'] = bdpiDomainMixedCase;
    m['bdpi_host_remove_spaces'] = bdpiHostRemoveSpaces;
    m['bdpi_tls_record_split'] = bdpiTlsRecordSplit;
    m['bdpi_tls_record_split_pos'] = bdpiTlsRecordSplitPos;
    m['bdpi_tls_record_split_sni'] = bdpiTlsRecordSplitAtSni;
    m['bdpi_fake_udp_count'] = bdpiFakeUdpCount;
    m['bdpi_strategy'] = bdpiStrategy;
    m['bdpi_mode_enabled'] = bdpiModeEnabled;

    return m;
  }

  // ── Импорт / экспорт настроек ByeDPI ────────────────────────────────────
  // Сериализуем только блок ByeDPI — это то, чем делятся (стратегии обхода).
  // Формат: {"teleopen_byedpi":1, ...поля...}. Версия позволит мигрировать.

  static const _kByeDpiExportTag = 'teleopen_byedpi';

  /// JSON-карта блока ByeDPI для экспорта (копирования/передачи).
  Map<String, dynamic> byeDpiToJson() => {
        _kByeDpiExportTag: 1,
        'maxConnections': bdpiMaxConnections,
        'bufferSize': bdpiBufferSize,
        'noDomain': bdpiNoDomain,
        'tcpFastOpen': bdpiTcpFastOpen,
        'hostsMode': bdpiHostsMode,
        'defaultTtl': bdpiDefaultTtl,
        'desyncMethod': bdpiDesyncMethod,
        'splitPosition': bdpiSplitPosition,
        'splitAtHost': bdpiSplitAtHost,
        'dropSack': bdpiDropSack,
        'desyncHttp': bdpiDesyncHttp,
        'desyncHttps': bdpiDesyncHttps,
        'desyncUdp': bdpiDesyncUdp,
        'hostMixedCase': bdpiHostMixedCase,
        'domainMixedCase': bdpiDomainMixedCase,
        'hostRemoveSpaces': bdpiHostRemoveSpaces,
        'tlsRecordSplit': bdpiTlsRecordSplit,
        'tlsRecordSplitPos': bdpiTlsRecordSplitPos,
        'tlsRecordSplitAtSni': bdpiTlsRecordSplitAtSni,
        'fakeUdpCount': bdpiFakeUdpCount,
        'strategy': bdpiStrategy,
      };

  /// Применяет JSON-карту блока ByeDPI (из импорта) к текущим настройкам.
  /// Неизвестные/отсутствующие ключи оставляют текущее значение. Бросает
  /// [FormatException], если это не наш экспорт ByeDPI.
  void applyByeDpiJson(Map<String, dynamic> j) {
    if (j[_kByeDpiExportTag] == null) {
      throw const FormatException('Не похоже на настройки ByeDPI');
    }
    String str(String k, String cur) => j[k] is String ? j[k] as String : cur;
    bool boolean(String k, bool cur) => j[k] is bool ? j[k] as bool : cur;

    bdpiMaxConnections = str('maxConnections', bdpiMaxConnections);
    bdpiBufferSize = str('bufferSize', bdpiBufferSize);
    bdpiNoDomain = boolean('noDomain', bdpiNoDomain);
    bdpiTcpFastOpen = boolean('tcpFastOpen', bdpiTcpFastOpen);
    bdpiHostsMode = str('hostsMode', bdpiHostsMode);
    bdpiDefaultTtl = str('defaultTtl', bdpiDefaultTtl);
    bdpiDesyncMethod = str('desyncMethod', bdpiDesyncMethod);
    bdpiSplitPosition = str('splitPosition', bdpiSplitPosition);
    bdpiSplitAtHost = boolean('splitAtHost', bdpiSplitAtHost);
    bdpiDropSack = boolean('dropSack', bdpiDropSack);
    bdpiDesyncHttp = boolean('desyncHttp', bdpiDesyncHttp);
    bdpiDesyncHttps = boolean('desyncHttps', bdpiDesyncHttps);
    bdpiDesyncUdp = boolean('desyncUdp', bdpiDesyncUdp);
    bdpiHostMixedCase = boolean('hostMixedCase', bdpiHostMixedCase);
    bdpiDomainMixedCase = boolean('domainMixedCase', bdpiDomainMixedCase);
    bdpiHostRemoveSpaces = boolean('hostRemoveSpaces', bdpiHostRemoveSpaces);
    bdpiTlsRecordSplit = boolean('tlsRecordSplit', bdpiTlsRecordSplit);
    bdpiTlsRecordSplitPos = str('tlsRecordSplitPos', bdpiTlsRecordSplitPos);
    bdpiTlsRecordSplitAtSni =
        boolean('tlsRecordSplitAtSni', bdpiTlsRecordSplitAtSni);
    bdpiFakeUdpCount = str('fakeUdpCount', bdpiFakeUdpCount);
    bdpiStrategy = str('strategy', bdpiStrategy);
  }
}

/// Строит аргументы командной строки для движка ciadpi (ByeDPI) из настроек.
///
/// Возвращает ТОЛЬКО опции десинхронизации/прокси; адрес и порт прослушивания
/// (`-i 127.0.0.1 -p <port>`) добавляет нативный слой при запуске.
///
/// ВНИМАНИЕ: буквы флагов соответствуют ciadpi (hufrea/byedpi) + расширениям
/// ByeByeDPI. При первой сборке свериться с `ciadpi --help` вендоренной версии —
/// весь маппинг изолирован здесь, правится в одном месте.
List<String> buildByeDpiArgs(AppSettings s) {
  // Готовая стратегия (пресет или своя) полностью замещает тумблеры —
  // отдаём её сырые аргументы как есть, токенизировав с учётом кавычек.
  final strategy = s.bdpiStrategy.trim();
  if (strategy.isNotEmpty) return tokenizeByeDpiArgs(strategy);

  final args = <String>[];

  int? toInt(String v) => int.tryParse(v.trim());

  // ── Прокси ────────────────────────────────────────────────────────────
  final maxConn = toInt(s.bdpiMaxConnections);
  if (maxConn != null && maxConn > 0) args.addAll(['-c', '$maxConn']);
  final buf = toInt(s.bdpiBufferSize);
  if (buf != null && buf > 0) args.addAll(['-b', '$buf']);
  if (s.bdpiNoDomain) args.add('-N');
  if (s.bdpiTcpFastOpen) args.add('-F');

  // ── Протоколы (область применения десинхронизации) ──────────────────────
  // -K <list>: t=TLS(HTTPS), h=HTTP, u=UDP/QUIC. Пусто — десинк не применяется.
  final proto = <String>[
    if (s.bdpiDesyncHttp) 'h',
    if (s.bdpiDesyncHttps) 't',
    if (s.bdpiDesyncUdp) 'u',
  ];
  if (proto.isNotEmpty) args.addAll(['-K', proto.join(',')]);

  // ── Десинхронизация: метод + позиция ────────────────────────────────────
  // Позиция может иметь суффикс относительной привязки: +h (host), +s (SNI).
  // «Разделить в хосте» → привязка к host; иначе оставляем абсолютное смещение.
  final posNum = toInt(s.bdpiSplitPosition) ?? 1;
  final pos = s.bdpiSplitAtHost ? '$posNum+h' : '$posNum';
  final methodFlag = switch (s.bdpiDesyncMethod) {
    'Split' => '-s',
    'Disorder' => '-d',
    'Fake' => '-f',
    'Out-of-band' => '-o',
    'Disorder out-of-band' => '-q',
    _ => null, // 'None'
  };
  if (methodFlag != null) {
    args.addAll([methodFlag, pos]);
    // TTL поддельных пакетов нужен методам, отправляющим fake/oob-сегменты.
    final ttl = toInt(s.bdpiDefaultTtl);
    if (ttl != null &&
        ttl > 0 &&
        (s.bdpiDesyncMethod == 'Fake' ||
            s.bdpiDesyncMethod == 'Out-of-band' ||
            s.bdpiDesyncMethod == 'Disorder out-of-band')) {
      args.addAll(['-t', '$ttl']);
    }
  }

  // Отбрасывать SACK (расширение ByeByeDPI).
  if (s.bdpiDropSack) args.add('--drop-sack');

  // Режим списка хостов: 'Белый'/'Чёрный' требуют файла со списком хостов,
  // UI которого пока нет. Когда появится — сюда добавить `-H <path>` (whitelist)
  // или эквивалент для blacklist. Сейчас режим 'Нет' = десинк ко всем хостам.

  // ── HTTP-модификации (-M / --mod-http) ──────────────────────────────────
  final mods = <String>[
    if (s.bdpiHostMixedCase) 'hcsmix',
    if (s.bdpiDomainMixedCase) 'dcsmix',
    if (s.bdpiHostRemoveSpaces) 'rmspace',
  ];
  if (mods.isNotEmpty) args.addAll(['-M', mods.join(',')]);

  // ── HTTPS: разбивка TLS-записи (-r <pos>, суффикс +s = по SNI) ───────────
  if (s.bdpiTlsRecordSplit) {
    final recPos = toInt(s.bdpiTlsRecordSplitPos) ?? 0;
    args.addAll(['-r', s.bdpiTlsRecordSplitAtSni ? '$recPos+s' : '$recPos']);
  }

  // ── UDP: количество поддельных датаграмм (-a <count>) ───────────────────
  final fakeUdp = toInt(s.bdpiFakeUdpCount);
  if (fakeUdp != null && fakeUdp > 0) args.addAll(['-a', '$fakeUdp']);

  return args;
}

// lib/state/app_settings.dart
//
// Модель пользовательских настроек приложения (соединение, маршрутизация,
// DNS, локальные порты, External Controller, функции Meta). Сериализуется в
// SharedPreferences и в Map для нативного ядра (mihomo/clash.meta).
//
// Вынесено из main.dart при разбиении монолита — поведение не менялось.

import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  // ── Соединение ──────────────────────────────────────────────────────────
  bool killSwitch;
  bool autoConnect;
  bool autoFailover;
  String dns;

  // ── Продвинутое ─────────────────────────────────────────────────────────
  bool packetAnalysis;
  bool useMux;

  // ── Маршрутизация ────────────────────────────────────────────────────────
  String region;
  String balancerStrategy;
  bool blockAds;
  bool bypassLan;
  bool resolveDestination;
  String ipv6Route;

  // ══════════════════════════════════════════════════════════════════════════
  // Расширенные настройки (mihomo / clash.meta).
  // Строковые поля используют sentinel-значение 'Не менять' = не подмешивать
  // в конфиг ядра (оставлять как в подписке).
  // ══════════════════════════════════════════════════════════════════════════

  // ── DNS: базовые (как было в dns_screen) ───────────────────────────────
  String dnsRemote;
  String dnsRemoteDomainStrategy;
  bool   dnsFakeDns;
  String dnsDirect;
  String dnsDirectDomainStrategy;

  // ── DNS: сервер ─────────────────────────────────────────────────────────
  bool   dnsTunHijackDns;
  bool   dnsAllowIncomingDomains;
  String dnsTestDomain;
  String dnsTtl;
  bool   dnsEnableRules;
  bool   dnsDirectStreamEcs;
  String dnsProxyResolveMode;        // FakeIP / RealIP

  // ── DNS: переопределение (sentinel 'Не менять') ────────────────────────
  String dnsPreferHttp3;
  String dnsRespectRules;
  String dnsUseSystemDns;
  String dnsIpv6Override;
  String dnsUseHosts;
  String dnsEnhancedMode;            // fake-ip / redir-host / Не менять
  String dnsNameserver;
  String dnsFallbackNameserver;
  String dnsDefaultNameserver;
  String dnsFakeIpFilter;
  String dnsFakeIpFilterMode;        // blacklist / whitelist / Не менять
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
  String metaGeoipPath;              // путь до импортированного файла
  String metaGeositePath;
  String metaCountryPath;
  String metaAsnPath;

  AppSettings({
    this.killSwitch = false,
    this.autoConnect = false,
    this.autoFailover = false,
    this.dns = '1.1.1.1',
    this.packetAnalysis = true,
    this.useMux = false,
    this.region = 'Россия (ru)',
    this.balancerStrategy = 'Round robin',
    this.blockAds = false,
    this.bypassLan = false,
    this.resolveDestination = false,
    this.ipv6Route = 'Отключить',

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
  });

  /// Поверхностная копия — пригодится экранам, которым нужна локальная
  /// рабочая копия, не мутирующая глобальный AppState до явного save.
  AppSettings.copy(AppSettings o)
      : killSwitch = o.killSwitch,
        autoFailover = o.autoFailover,
        autoConnect = o.autoConnect,
        dns = o.dns,
        packetAnalysis = o.packetAnalysis,
        useMux = o.useMux,
        region = o.region,
        balancerStrategy = o.balancerStrategy,
        blockAds = o.blockAds,
        bypassLan = o.bypassLan,
        resolveDestination = o.resolveDestination,
        ipv6Route = o.ipv6Route,
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
        metaAsnPath = o.metaAsnPath;

  static AppSettings fromPrefs(SharedPreferences p) => AppSettings(
        killSwitch:         p.getBool('s_killSwitch') ?? false,
        autoConnect:        p.getBool('s_autoConnect') ?? false,
        autoFailover:       p.getBool('s_autoFailover') ?? false,
        dns:                p.getString('s_dns') ?? '1.1.1.1',
        packetAnalysis:     p.getBool('s_packetAnalysis') ?? true,
        useMux:             p.getBool('s_useMux') ?? false,
        region:             p.getString('s_region') ?? 'Россия (ru)',
        balancerStrategy:   p.getString('s_balancerStrategy') ?? 'Round robin',
        blockAds:           p.getBool('s_blockAds') ?? false,
        bypassLan:          p.getBool('s_bypassLan') ?? false,
        resolveDestination: p.getBool('s_resolveDestination') ?? false,
        ipv6Route:          p.getString('s_ipv6Route') ?? 'Отключить',

        // DNS basic
        dnsRemote:                p.getString('s_dnsRemote') ?? 'tcp://8.8.8.8',
        dnsRemoteDomainStrategy:  p.getString('s_dnsRemoteDomainStrategy') ?? 'Авто',
        dnsFakeDns:               p.getBool('s_dnsFakeDns') ?? false,
        dnsDirect:                p.getString('s_dnsDirect') ?? '1.1.1.1',
        dnsDirectDomainStrategy:  p.getString('s_dnsDirectDomainStrategy') ?? 'Авто',

        // DNS server
        dnsTunHijackDns:         p.getBool('s_dnsTunHijackDns') ?? true,
        dnsAllowIncomingDomains: p.getBool('s_dnsAllowIncomingDomains') ?? false,
        dnsTestDomain:           p.getString('s_dnsTestDomain') ?? 'gstatic.com',
        dnsTtl:                  p.getString('s_dnsTtl') ?? '12 h',
        dnsEnableRules:          p.getBool('s_dnsEnableRules') ?? false,
        dnsDirectStreamEcs:      p.getBool('s_dnsDirectStreamEcs') ?? true,
        dnsProxyResolveMode:     p.getString('s_dnsProxyResolveMode') ?? 'FakeIP',

        // DNS override
        dnsPreferHttp3:        p.getString('s_dnsPreferHttp3') ?? 'Не менять',
        dnsRespectRules:       p.getString('s_dnsRespectRules') ?? 'Не менять',
        dnsUseSystemDns:       p.getString('s_dnsUseSystemDns') ?? 'Не менять',
        dnsIpv6Override:       p.getString('s_dnsIpv6Override') ?? 'Не менять',
        dnsUseHosts:           p.getString('s_dnsUseHosts') ?? 'Не менять',
        dnsEnhancedMode:       p.getString('s_dnsEnhancedMode') ?? 'Не менять',
        dnsNameserver:         p.getString('s_dnsNameserver') ?? 'Не менять',
        dnsFallbackNameserver: p.getString('s_dnsFallbackNameserver') ?? 'Не менять',
        dnsDefaultNameserver:  p.getString('s_dnsDefaultNameserver') ?? 'Не менять',
        dnsFakeIpFilter:       p.getString('s_dnsFakeIpFilter') ?? 'Не менять',
        dnsFakeIpFilterMode:   p.getString('s_dnsFakeIpFilterMode') ?? 'Не менять',
        dnsFallbackGeoip:      p.getString('s_dnsFallbackGeoip') ?? 'Не менять',
        dnsFallbackGeoipCode:  p.getString('s_dnsFallbackGeoipCode') ?? 'Не менять',
        dnsFallbackDomain:     p.getString('s_dnsFallbackDomain') ?? 'Не менять',
        dnsFallbackIpcidr:     p.getString('s_dnsFallbackIpcidr') ?? 'Не менять',
        dnsNameserverPolicy:   p.getString('s_dnsNameserverPolicy') ?? 'Не менять',

        // Network
        netRouteSystemTraffic: p.getBool('s_netRouteSystemTraffic') ?? true,
        netBypassPrivate:      p.getBool('s_netBypassPrivate') ?? true,
        netHijackDns:          p.getBool('s_netHijackDns') ?? true,
        netAllowBypass:        p.getBool('s_netAllowBypass') ?? true,
        netAllowIpv6:          p.getBool('s_netAllowIpv6') ?? false,
        netSystemProxy:        p.getBool('s_netSystemProxy') ?? true,

        // Local ports
        portHttp:        p.getString('s_portHttp') ?? 'Не менять',
        portSocks:       p.getString('s_portSocks') ?? 'Не менять',
        portRedir:       p.getString('s_portRedir') ?? 'Не менять',
        portTproxy:      p.getString('s_portTproxy') ?? 'Не менять',
        portMixed:       p.getString('s_portMixed') ?? 'Не менять',
        portAuth:        p.getString('s_portAuth') ?? 'Не менять',
        portAllowLan:    p.getString('s_portAllowLan') ?? 'Не менять',
        portIpv6:        p.getString('s_portIpv6') ?? 'Не менять',
        portBindAddress: p.getString('s_portBindAddress') ?? 'Не менять',

        // External Controller
        ecAddress:             p.getString('s_ecAddress') ?? 'Не менять',
        ecAddressTls:          p.getString('s_ecAddressTls') ?? 'Не менять',
        ecAllowOrigins:        p.getString('s_ecAllowOrigins') ?? 'Не менять',
        ecAllowPrivateNetwork: p.getString('s_ecAllowPrivateNetwork') ?? 'Не менять',
        ecSecret:              p.getString('s_ecSecret') ?? 'Не менять',
        ecMode:                p.getString('s_ecMode') ?? 'Не менять',
        ecLogLevel:            p.getString('s_ecLogLevel') ?? 'Не менять',
        ecHosts:               p.getString('s_ecHosts') ?? 'Не менять',

        // Meta
        metaUnifiedDelay:        p.getString('s_metaUnifiedDelay') ?? 'Не менять',
        metaGeoMode:             p.getString('s_metaGeoMode') ?? 'Не менять',
        metaMptcp:               p.getString('s_metaMptcp') ?? 'Не менять',
        metaFindProcess:         p.getString('s_metaFindProcess') ?? 'Не менять',
        metaStrategy:            p.getString('s_metaStrategy') ?? 'Не менять',
        metaSniffHttpPorts:      p.getString('s_metaSniffHttpPorts') ?? 'Не менять',
        metaSniffHttpOverride:   p.getString('s_metaSniffHttpOverride') ?? 'Не менять',
        metaSniffTlsPorts:       p.getString('s_metaSniffTlsPorts') ?? 'Не менять',
        metaSniffTlsOverride:    p.getString('s_metaSniffTlsOverride') ?? 'Не менять',
        metaSniffQuicPorts:      p.getString('s_metaSniffQuicPorts') ?? 'Не менять',
        metaSniffQuicOverride:   p.getString('s_metaSniffQuicOverride') ?? 'Не менять',
        metaForceDnsMapping:     p.getString('s_metaForceDnsMapping') ?? 'Не менять',
        metaParsePureIp:         p.getString('s_metaParsePureIp') ?? 'Не менять',
        metaOverrideDestination: p.getString('s_metaOverrideDestination') ?? 'Не менять',
        metaForceDomain:         p.getString('s_metaForceDomain') ?? 'Не менять',
        metaSkipDomain:          p.getString('s_metaSkipDomain') ?? 'Не менять',
        metaSkipSrc:             p.getString('s_metaSkipSrc') ?? 'Не менять',
        metaSkipDst:             p.getString('s_metaSkipDst') ?? 'Не менять',
        metaGeoipPath:           p.getString('s_metaGeoipPath') ?? '',
        metaGeositePath:         p.getString('s_metaGeositePath') ?? '',
        metaCountryPath:         p.getString('s_metaCountryPath') ?? '',
        metaAsnPath:             p.getString('s_metaAsnPath') ?? '',
      );

  void save(SharedPreferences p) {
    p.setBool('s_killSwitch', killSwitch);
    p.setBool('s_autoConnect', autoConnect);
    p.setBool('s_autoFailover', autoFailover);
    p.setString('s_dns', dns);
    p.setBool('s_packetAnalysis', packetAnalysis);
    p.setBool('s_useMux', useMux);
    p.setString('s_region', region);
    p.setString('s_balancerStrategy', balancerStrategy);
    p.setBool('s_blockAds', blockAds);
    p.setBool('s_bypassLan', bypassLan);
    p.setBool('s_resolveDestination', resolveDestination);
    p.setString('s_ipv6Route', ipv6Route);

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
    p.setString('s_portAuth', portAuth);
    p.setString('s_portAllowLan', portAllowLan);
    p.setString('s_portIpv6', portIpv6);
    p.setString('s_portBindAddress', portBindAddress);

    // External Controller
    p.setString('s_ecAddress', ecAddress);
    p.setString('s_ecAddressTls', ecAddressTls);
    p.setString('s_ecAllowOrigins', ecAllowOrigins);
    p.setString('s_ecAllowPrivateNetwork', ecAllowPrivateNetwork);
    p.setString('s_ecSecret', ecSecret);
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
    if (metaGeoipPath.isNotEmpty)   m['meta_geoip_path']   = metaGeoipPath;
    if (metaGeositePath.isNotEmpty) m['meta_geosite_path'] = metaGeositePath;
    if (metaCountryPath.isNotEmpty) m['meta_country_path'] = metaCountryPath;
    if (metaAsnPath.isNotEmpty)     m['meta_asn_path']     = metaAsnPath;

    return m;
  }
}

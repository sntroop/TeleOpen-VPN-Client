import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ios_theme.dart';
import 'vpn_bridge.dart';
import 'models/vpn_node.dart';
import 'models/per_app_proxy.dart';
import 'models/market.dart';
import 'models/mtproto_proxy.dart';
import 'logic/parsers.dart';
import 'logic/subscriptions.dart';
import 'logic/crash_log.dart';
import 'logic/ping.dart';
import 'logic/hysteria2.dart';
import 'logic/market_api.dart';
import 'screens/home_screen.dart';
import 'screens/statistics_screen.dart';

import 'logic/theme_storage.dart';
import 'models/theme.dart' as theme_model;

Future<void> main() async {
  
  
  
  
  
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('=== FlutterError: ${details.exception}\n${details.stack}');
      CrashLog.record(details.exception, details.stack, 'flutter');
    };

    
    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      debugPrint('=== PlatformDispatcher error: $error\n$stack');
      CrashLog.record(error, stack, 'platform');
      return true; 
    };

    final prefs = await SharedPreferences.getInstance();
    CrashLog.attach(prefs);

    final modeStr = prefs.getString('theme_mode') ?? 'system';
    final initialMode = switch (modeStr) {
      'light' => IosThemeMode.light,
      'dark'  => IosThemeMode.dark,
      _       => IosThemeMode.system,
    };

    
    final savedTheme = await ThemeStorage.load();

    runApp(TeleOpenApp(
      initialThemeMode: initialMode,
      prefs: prefs,
      savedTheme: savedTheme,
    ));
  }, (Object error, StackTrace stack) {
    
    debugPrint('=== UNCAUGHT (zone): $error\n$stack');
    CrashLog.record(error, stack, 'zone');
  });
}

class TeleOpenApp extends StatefulWidget {
  final IosThemeMode initialThemeMode;
  final SharedPreferences prefs;
  final theme_model.UserTheme? savedTheme;
  const TeleOpenApp({
    super.key,
    required this.initialThemeMode,
    required this.prefs,
    this.savedTheme,
  });

  @override
  State<TeleOpenApp> createState() => _TeleOpenAppState();
}

class _TeleOpenAppState extends State<TeleOpenApp> {
  @override
  void initState() {
    super.initState();
    if (widget.savedTheme != null) {
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        IosThemeScope.of(context).setCustomTheme(
            widget.savedTheme!.toIosThemeData());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = widget.prefs;
    return IosThemeScope(
      initialMode: widget.initialThemeMode,
      onModeChanged: (m) {
        prefs.setString('theme_mode', switch (m) {
          IosThemeMode.light => 'light',
          IosThemeMode.dark  => 'dark',
          IosThemeMode.system => 'system',
        });
      },
      child: AppStateScope(
        prefs: prefs,
        child: Builder(
          builder: (ctx) {
            final t = IosTheme.of(ctx);
            final c = t.colors;
            final baseText = t.textStyles.body;
            return MaterialApp(
              title: 'TeleOpen',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                brightness: t.brightness,
                scaffoldBackgroundColor: c.bgPrimary,
                canvasColor: c.bgPrimary,
                textTheme: TextTheme(
                  displayLarge:  baseText, displayMedium: baseText, displaySmall:  baseText,
                  headlineLarge: baseText, headlineMedium: baseText, headlineSmall: baseText,
                  titleLarge:    t.textStyles.title2,
                  titleMedium:   t.textStyles.headline,
                  titleSmall:    t.textStyles.subheadline,
                  bodyLarge:     baseText, bodyMedium: baseText, bodySmall: t.textStyles.footnote,
                  labelLarge:    t.textStyles.headline,
                  labelMedium:   t.textStyles.footnote,
                  labelSmall:    t.textStyles.caption1,
                ),
                primaryColor: c.blue,
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
              ),
              builder: (context, child) {
                return DefaultTextStyle(
                  style: baseText,
                  child: child ?? const SizedBox.shrink(),
                );
              },
              home: const HomeScreen(),
            );
          },
        ),
      ),
    );
  }
}

enum VpnStatus { stopped, connecting, connected, error }

class AppSettings {
  
  bool killSwitch;
  bool autoConnect;
  String dns;

  
  bool packetAnalysis;
  bool useMux;

  
  String region;
  String balancerStrategy;
  bool blockAds;
  bool bypassLan;
  bool resolveDestination;
  String ipv6Route;

  
  
  
  
  

  
  String dnsRemote;
  String dnsRemoteDomainStrategy;
  bool   dnsFakeDns;
  String dnsDirect;
  String dnsDirectDomainStrategy;

  
  bool   dnsTunHijackDns;
  bool   dnsAllowIncomingDomains;
  String dnsTestDomain;
  String dnsTtl;
  bool   dnsEnableRules;
  bool   dnsDirectStreamEcs;
  String dnsProxyResolveMode;        

  
  String dnsPreferHttp3;
  String dnsRespectRules;
  String dnsUseSystemDns;
  String dnsIpv6Override;
  String dnsUseHosts;
  String dnsEnhancedMode;            
  String dnsNameserver;
  String dnsFallbackNameserver;
  String dnsDefaultNameserver;
  String dnsFakeIpFilter;
  String dnsFakeIpFilterMode;        
  String dnsFallbackGeoip;
  String dnsFallbackGeoipCode;
  String dnsFallbackDomain;
  String dnsFallbackIpcidr;
  String dnsNameserverPolicy;

  
  bool netRouteSystemTraffic;
  bool netBypassPrivate;
  bool netHijackDns;
  bool netAllowBypass;
  bool netAllowIpv6;
  bool netSystemProxy;

  
  String portHttp;
  String portSocks;
  String portRedir;
  String portTproxy;
  String portMixed;
  String portAuth;
  String portAllowLan;
  String portIpv6;
  String portBindAddress;

  
  String ecAddress;
  String ecAddressTls;
  String ecAllowOrigins;
  String ecAllowPrivateNetwork;
  String ecSecret;
  String ecMode;
  String ecLogLevel;
  String ecHosts;

  
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
  String metaGeoipPath;              
  String metaGeositePath;
  String metaCountryPath;
  String metaAsnPath;

  AppSettings({
    this.killSwitch = false,
    this.autoConnect = false,
    this.dns = '1.1.1.1',
    this.packetAnalysis = true,
    this.useMux = false,
    this.region = 'Россия (ru)',
    this.balancerStrategy = 'Round robin',
    this.blockAds = false,
    this.bypassLan = false,
    this.resolveDestination = false,
    this.ipv6Route = 'Отключить',

    
    this.dnsRemote = 'tcp://8.8.8.8',
    this.dnsRemoteDomainStrategy = 'Авто',
    this.dnsFakeDns = false,
    this.dnsDirect = '1.1.1.1',
    this.dnsDirectDomainStrategy = 'Авто',

    
    this.dnsTunHijackDns = true,
    this.dnsAllowIncomingDomains = false,
    this.dnsTestDomain = 'gstatic.com',
    this.dnsTtl = '12 h',
    this.dnsEnableRules = false,
    this.dnsDirectStreamEcs = true,
    this.dnsProxyResolveMode = 'FakeIP',

    
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

    
    this.netRouteSystemTraffic = true,
    this.netBypassPrivate = true,
    this.netHijackDns = true,
    this.netAllowBypass = true,
    this.netAllowIpv6 = false,
    this.netSystemProxy = true,

    
    this.portHttp = 'Не менять',
    this.portSocks = 'Не менять',
    this.portRedir = 'Не менять',
    this.portTproxy = 'Не менять',
    this.portMixed = 'Не менять',
    this.portAuth = 'Не менять',
    this.portAllowLan = 'Не менять',
    this.portIpv6 = 'Не менять',
    this.portBindAddress = 'Не менять',

    
    this.ecAddress = 'Не менять',
    this.ecAddressTls = 'Не менять',
    this.ecAllowOrigins = 'Не менять',
    this.ecAllowPrivateNetwork = 'Не менять',
    this.ecSecret = 'Не менять',
    this.ecMode = 'Не менять',
    this.ecLogLevel = 'Не менять',
    this.ecHosts = 'Не менять',

    
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

  
  
  AppSettings.copy(AppSettings o)
      : killSwitch = o.killSwitch,
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
        dns:                p.getString('s_dns') ?? '1.1.1.1',
        packetAnalysis:     p.getBool('s_packetAnalysis') ?? true,
        useMux:             p.getBool('s_useMux') ?? false,
        region:             p.getString('s_region') ?? 'Россия (ru)',
        balancerStrategy:   p.getString('s_balancerStrategy') ?? 'Round robin',
        blockAds:           p.getBool('s_blockAds') ?? false,
        bypassLan:          p.getBool('s_bypassLan') ?? false,
        resolveDestination: p.getBool('s_resolveDestination') ?? false,
        ipv6Route:          p.getString('s_ipv6Route') ?? 'Отключить',

        
        dnsRemote:                p.getString('s_dnsRemote') ?? 'tcp://8.8.8.8',
        dnsRemoteDomainStrategy:  p.getString('s_dnsRemoteDomainStrategy') ?? 'Авто',
        dnsFakeDns:               p.getBool('s_dnsFakeDns') ?? false,
        dnsDirect:                p.getString('s_dnsDirect') ?? '1.1.1.1',
        dnsDirectDomainStrategy:  p.getString('s_dnsDirectDomainStrategy') ?? 'Авто',

        
        dnsTunHijackDns:         p.getBool('s_dnsTunHijackDns') ?? true,
        dnsAllowIncomingDomains: p.getBool('s_dnsAllowIncomingDomains') ?? false,
        dnsTestDomain:           p.getString('s_dnsTestDomain') ?? 'gstatic.com',
        dnsTtl:                  p.getString('s_dnsTtl') ?? '12 h',
        dnsEnableRules:          p.getBool('s_dnsEnableRules') ?? false,
        dnsDirectStreamEcs:      p.getBool('s_dnsDirectStreamEcs') ?? true,
        dnsProxyResolveMode:     p.getString('s_dnsProxyResolveMode') ?? 'FakeIP',

        
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

        
        netRouteSystemTraffic: p.getBool('s_netRouteSystemTraffic') ?? true,
        netBypassPrivate:      p.getBool('s_netBypassPrivate') ?? true,
        netHijackDns:          p.getBool('s_netHijackDns') ?? true,
        netAllowBypass:        p.getBool('s_netAllowBypass') ?? true,
        netAllowIpv6:          p.getBool('s_netAllowIpv6') ?? false,
        netSystemProxy:        p.getBool('s_netSystemProxy') ?? true,

        
        portHttp:        p.getString('s_portHttp') ?? 'Не менять',
        portSocks:       p.getString('s_portSocks') ?? 'Не менять',
        portRedir:       p.getString('s_portRedir') ?? 'Не менять',
        portTproxy:      p.getString('s_portTproxy') ?? 'Не менять',
        portMixed:       p.getString('s_portMixed') ?? 'Не менять',
        portAuth:        p.getString('s_portAuth') ?? 'Не менять',
        portAllowLan:    p.getString('s_portAllowLan') ?? 'Не менять',
        portIpv6:        p.getString('s_portIpv6') ?? 'Не менять',
        portBindAddress: p.getString('s_portBindAddress') ?? 'Не менять',

        
        ecAddress:             p.getString('s_ecAddress') ?? 'Не менять',
        ecAddressTls:          p.getString('s_ecAddressTls') ?? 'Не менять',
        ecAllowOrigins:        p.getString('s_ecAllowOrigins') ?? 'Не менять',
        ecAllowPrivateNetwork: p.getString('s_ecAllowPrivateNetwork') ?? 'Не менять',
        ecSecret:              p.getString('s_ecSecret') ?? 'Не менять',
        ecMode:                p.getString('s_ecMode') ?? 'Не менять',
        ecLogLevel:            p.getString('s_ecLogLevel') ?? 'Не менять',
        ecHosts:               p.getString('s_ecHosts') ?? 'Не менять',

        
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
    p.setString('s_dns', dns);
    p.setBool('s_packetAnalysis', packetAnalysis);
    p.setBool('s_useMux', useMux);
    p.setString('s_region', region);
    p.setString('s_balancerStrategy', balancerStrategy);
    p.setBool('s_blockAds', blockAds);
    p.setBool('s_bypassLan', bypassLan);
    p.setBool('s_resolveDestination', resolveDestination);
    p.setString('s_ipv6Route', ipv6Route);

    
    p.setString('s_dnsRemote', dnsRemote);
    p.setString('s_dnsRemoteDomainStrategy', dnsRemoteDomainStrategy);
    p.setBool('s_dnsFakeDns', dnsFakeDns);
    p.setString('s_dnsDirect', dnsDirect);
    p.setString('s_dnsDirectDomainStrategy', dnsDirectDomainStrategy);

    
    p.setBool('s_dnsTunHijackDns', dnsTunHijackDns);
    p.setBool('s_dnsAllowIncomingDomains', dnsAllowIncomingDomains);
    p.setString('s_dnsTestDomain', dnsTestDomain);
    p.setString('s_dnsTtl', dnsTtl);
    p.setBool('s_dnsEnableRules', dnsEnableRules);
    p.setBool('s_dnsDirectStreamEcs', dnsDirectStreamEcs);
    p.setString('s_dnsProxyResolveMode', dnsProxyResolveMode);

    
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

    
    p.setBool('s_netRouteSystemTraffic', netRouteSystemTraffic);
    p.setBool('s_netBypassPrivate', netBypassPrivate);
    p.setBool('s_netHijackDns', netHijackDns);
    p.setBool('s_netAllowBypass', netAllowBypass);
    p.setBool('s_netAllowIpv6', netAllowIpv6);
    p.setBool('s_netSystemProxy', netSystemProxy);

    
    p.setString('s_portHttp', portHttp);
    p.setString('s_portSocks', portSocks);
    p.setString('s_portRedir', portRedir);
    p.setString('s_portTproxy', portTproxy);
    p.setString('s_portMixed', portMixed);
    p.setString('s_portAuth', portAuth);
    p.setString('s_portAllowLan', portAllowLan);
    p.setString('s_portIpv6', portIpv6);
    p.setString('s_portBindAddress', portBindAddress);

    
    p.setString('s_ecAddress', ecAddress);
    p.setString('s_ecAddressTls', ecAddressTls);
    p.setString('s_ecAllowOrigins', ecAllowOrigins);
    p.setString('s_ecAllowPrivateNetwork', ecAllowPrivateNetwork);
    p.setString('s_ecSecret', ecSecret);
    p.setString('s_ecMode', ecMode);
    p.setString('s_ecLogLevel', ecLogLevel);
    p.setString('s_ecHosts', ecHosts);

    
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

  
  
  Map<String, dynamic> toCoreConfig() {
    final m = <String, dynamic>{};

    void putStr(String key, String v) {
      if (v.isNotEmpty && v != 'Не менять') m[key] = v;
    }

    
    m['kill_switch'] = killSwitch;
    m['auto_connect'] = autoConnect;
    m['dns_system'] = dns;
    m['packet_analysis'] = packetAnalysis;
    m['use_mux'] = useMux;
    m['region'] = region;
    m['balancer_strategy'] = balancerStrategy;
    m['block_ads'] = blockAds;
    m['bypass_lan'] = bypassLan;
    m['resolve_destination'] = resolveDestination;
    m['ipv6_route'] = ipv6Route;

    
    m['dns_remote'] = dnsRemote;
    m['dns_remote_strategy'] = dnsRemoteDomainStrategy;
    m['dns_fake'] = dnsFakeDns;
    m['dns_direct'] = dnsDirect;
    m['dns_direct_strategy'] = dnsDirectDomainStrategy;

    
    m['dns_tun_hijack'] = dnsTunHijackDns;
    m['dns_allow_incoming_domains'] = dnsAllowIncomingDomains;
    m['dns_test_domain'] = dnsTestDomain;
    m['dns_ttl'] = dnsTtl;
    m['dns_enable_rules'] = dnsEnableRules;
    m['dns_direct_ecs'] = dnsDirectStreamEcs;
    m['dns_proxy_resolve_mode'] = dnsProxyResolveMode;

    
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

    
    m['net_route_system'] = netRouteSystemTraffic;
    m['net_bypass_private'] = netBypassPrivate;
    m['net_hijack_dns'] = netHijackDns;
    m['net_allow_bypass'] = netAllowBypass;
    m['net_allow_ipv6'] = netAllowIpv6;
    m['net_system_proxy'] = netSystemProxy;

    
    putStr('port_http', portHttp);
    putStr('port_socks', portSocks);
    putStr('port_redir', portRedir);
    putStr('port_tproxy', portTproxy);
    putStr('port_mixed', portMixed);
    putStr('port_auth', portAuth);
    putStr('port_allow_lan', portAllowLan);
    putStr('port_ipv6', portIpv6);
    putStr('port_bind_address', portBindAddress);

    
    putStr('ec_address', ecAddress);
    putStr('ec_address_tls', ecAddressTls);
    putStr('ec_allow_origins', ecAllowOrigins);
    putStr('ec_allow_private', ecAllowPrivateNetwork);
    putStr('ec_secret', ecSecret);
    putStr('ec_mode', ecMode);
    putStr('ec_log_level', ecLogLevel);
    putStr('ec_hosts', ecHosts);

    
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

class AppState extends ChangeNotifier {
  final SharedPreferences prefs;
  final VpnBridge bridge = VpnBridge();

  VpnStatus status = VpnStatus.stopped;
  VpnNode? activeNode;
  List<VpnGroup> groups = [];
  List<MtProtoProxyGroup> mtProtoGroups = [];
  Set<String> favoriteIds = {};
  AppSettings settings;
  PerAppProxySettings perApp;
  TgUser? currentUser;
  Duration connectionDuration = Duration.zero;
  VpnStats currentStats = VpnStats.zero;
  Timer? _timer;
  String? lastError;
  bool _pinging = false;
  bool get isPinging => _pinging;

  
  DateTime? _sessionStart;

  AppState(this.prefs)
      : settings = AppSettings.fromPrefs(prefs),
        perApp = _loadPerApp(prefs) {
    _loadFavorites();
    _loadGroups();
    _loadMtProtoGroups();
    _loadUser();
    _initBridge();
    if (settings.autoConnect) _autoConnect();
  }

  void _loadFavorites() {
    favoriteIds = prefs.getStringList('favorites')?.toSet() ?? {};
  }

  void _loadGroups() {
    final s = prefs.getString('groups') ?? '';
    try {
      groups = VpnGroup.decode(s);
      for (final g in groups) {
        for (final n in g.nodes) {
          n.isFavorite = favoriteIds.contains(n.id);
          n.groupId = g.id;
        }
      }
    } catch (_) {
      groups = [];
    }
  }

  void _saveGroups() {
    prefs.setString('groups', VpnGroup.encode(groups));
  }

  

  void _loadMtProtoGroups() {
    final s = prefs.getString('mtproto_groups') ?? '';
    try {
      mtProtoGroups = MtProtoProxyGroup.decode(s);
    } catch (_) {
      
      mtProtoGroups = [];
    }
  }

  void _saveMtProtoGroups() {
    prefs.setString('mtproto_groups', MtProtoProxyGroup.encode(mtProtoGroups));
  }

  
  void addMtProtoGroup(MtProtoProxyGroup group) {
    mtProtoGroups.add(group);
    _saveMtProtoGroups();
    notifyListeners();
  }

  
  void removeMtProtoGroup(String groupId) {
    mtProtoGroups.removeWhere((g) => g.id == groupId);
    _saveMtProtoGroups();
    notifyListeners();
  }

  
  void addMtProtoProxy(MtProtoProxy proxy, {String? toGroupId}) {
    MtProtoProxyGroup group;
    if (toGroupId != null) {
      group = mtProtoGroups.firstWhere(
        (g) => g.id == toGroupId,
        orElse: () => _ensureDefaultMtProtoGroup(),
      );
    } else {
      group = _ensureDefaultMtProtoGroup();
    }
    group.proxies.add(proxy);
    _saveMtProtoGroups();
    notifyListeners();
  }

  
  void removeMtProtoProxy(String groupId, MtProtoProxy proxy) {
    final group = mtProtoGroups
        .where((g) => g.id == groupId)
        .cast<MtProtoProxyGroup?>()
        .firstOrNull;
    if (group == null) return;
    group.proxies.remove(proxy);
    if (group.proxies.isEmpty) {
      mtProtoGroups.remove(group);
    }
    _saveMtProtoGroups();
    notifyListeners();
  }

  
  void persistMtProtoGroups() {
    _saveMtProtoGroups();
    notifyListeners();
  }

  
  
  
  void toggleFavoriteMtProto(MtProtoProxy proxy) {
    proxy.isFavorite = !proxy.isFavorite;
    _saveMtProtoGroups();
    notifyListeners();
  }

  MtProtoProxyGroup _ensureDefaultMtProtoGroup() {
    if (mtProtoGroups.isNotEmpty) return mtProtoGroups.first;
    final g = MtProtoProxyGroup(
      id: 'mtproto_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Мои прокси',
      proxies: [],
    );
    mtProtoGroups.add(g);
    return g;
  }

  static PerAppProxySettings _loadPerApp(SharedPreferences p) {
    final s = p.getString('per_app_proxy');
    if (s == null || s.isEmpty) return PerAppProxySettings();
    try {
      final m = (jsonDecode(s) as Map).cast<String, dynamic>();
      return PerAppProxySettings.fromJson(m);
    } catch (_) {
      return PerAppProxySettings();
    }
  }

  void setPerAppProxy(PerAppProxySettings s) {
    perApp = s;
    prefs.setString('per_app_proxy', jsonEncode(s.toJson()));
    notifyListeners();
  }

  void _loadUser() {
    final s = prefs.getString('tg_user');
    if (s == null || s.isEmpty) return;
    try {
      currentUser = TgUser.fromJson((jsonDecode(s) as Map).cast<String, dynamic>());
      
      final jwt = prefs.getString('jwt');
      if (jwt != null && jwt.isNotEmpty) {
        MarketApi.setJwt(jwt);
      }
    } catch (_) {}
  }

  void setUser(TgUser u, {String? jwt}) {
    currentUser = u;
    prefs.setString('tg_user', jsonEncode(u.toJson()));
    if (jwt != null && jwt.isNotEmpty) {
      prefs.setString('jwt', jwt);
      MarketApi.setJwt(jwt);
    }
    notifyListeners();
  }

  void logout() {
    currentUser = null;
    prefs.remove('tg_user');
    prefs.remove('jwt');
    MarketApi.setJwt(null);
    notifyListeners();
  }

  Future<void> _initBridge() async {
    await bridge.init(
      onStatus: (s) {
        final newStatus = switch (s.toUpperCase()) {
          'CONNECTING' => VpnStatus.connecting,
          'CONNECTED'  => VpnStatus.connected,
          _            => VpnStatus.stopped,
        };
        if (status != newStatus) {
          status = newStatus;
          if (newStatus == VpnStatus.connected) {
            _startTimer();
            _sessionStart = DateTime.now();
          } else {
            
            _sessionStart = null;
            _stopTimer();
            currentStats = VpnStats.zero;
          }
          notifyListeners();
        }
      },
      onStats: (s) {
        currentStats = s;
        notifyListeners();
      },
    );
    
    
    
    bridge.applyCoreConfig(settings.toCoreConfig());
  }

  Future<void> _autoConnect() async {
    final lastId = prefs.getString('last_active_node');
    if (lastId == null) return;
    final node = _findNode(lastId);
    if (node != null) await connect(node);
  }

  VpnNode? _findNode(String id) {
    for (final g in groups) {
      for (final n in g.nodes) {
        if (n.id == id) return n;
      }
    }
    return null;
  }

  

  Future<void> connect(VpnNode node) async {
    if (status == VpnStatus.connecting) return;
    if (status == VpnStatus.connected) {
      await disconnect();
      await Future.delayed(const Duration(milliseconds: 300));
    }
    activeNode = node;
    status = VpnStatus.connecting;
    lastError = null;
    prefs.setString('last_active_node', node.id);
    notifyListeners();

    try {
      
      final perAppOn = perApp.enabled;
      final allowedPkgs = perAppOn ? perApp.includedPackages : const <String>[];

      if (node.protocol == VpnProtocol.hysteria2) {
        final hyOk = await Hysteria2Manager.start(node.rawUri);
        if (!hyOk) throw Exception('Не удалось запустить Hysteria2');
        final ok = await bridge.start(
          socks5Port: Hysteria2Manager.socks5Port,
          remark: node.name,
          perAppEnabled: perAppOn,
          allowedPackages: allowedPkgs,
        );
        if (!ok) {
          await Hysteria2Manager.stop();
          throw Exception('Не удалось запустить TUN VpnService');
        }
      } else {
        final config = buildXrayConfig(
          node,
          packetSniffing: settings.packetAnalysis,
          useMux: settings.useMux,
        );
        final ok = await bridge.startV2Ray(
          config: config,
          remark: node.name,
          perAppEnabled: perAppOn,
          allowedPackages: allowedPkgs,
        );
        if (!ok) throw Exception('Не удалось запустить xray');
      }
    } catch (e) {
      lastError = e.toString();
      status = VpnStatus.error;
      notifyListeners();
      await Future.delayed(const Duration(seconds: 2));
      status = VpnStatus.stopped;
      notifyListeners();
    }
  }

  Future<void> setActiveOnly(VpnNode node) async {
    if (status == VpnStatus.connecting) return;
    if (status == VpnStatus.connected && activeNode?.id != node.id) {
      await connect(node);
      return;
    }
    activeNode = node;
    prefs.setString('last_active_node', node.id);
    notifyListeners();
  }

  Future<void> disconnect() async {
    
    final sessionStart = _sessionStart;
    final node = activeNode;
    final stats = currentStats;
    _sessionStart = null;

    if (sessionStart != null && node != null) {
      final durationSec = DateTime.now().difference(sessionStart).inSeconds;
      if (durationSec > 0) {
        final record = SessionRecord(
          nodeId:      node.id,
          nodeName:    node.name,
          protocol:    node.protocol.name,
          startedAt:   sessionStart,
          durationSec: durationSec,
          rxBytes:     stats.rxBytes,
          txBytes:     stats.txBytes,
        );
        
        SessionStorage.append(prefs, record);
      }
    }

    await bridge.stop();
    await Hysteria2Manager.stop();
    activeNode = null;
    status = VpnStatus.stopped;
    _stopTimer();
    notifyListeners();
  }

  

  void toggleFavorite(VpnNode n) {
    n.isFavorite = !n.isFavorite;
    if (n.isFavorite) {
      favoriteIds.add(n.id);
    } else {
      favoriteIds.remove(n.id);
    }
    prefs.setStringList('favorites', favoriteIds.toList());
    notifyListeners();
  }

  

  Future<String?> addSubscription({required String url, String? title}) async {
    final result = await SubscriptionLoader.load(url);
    if (result.error != null) return result.error;
    if (result.nodes.isEmpty) return 'Не найдено серверов';

    final groupTitle = (title?.isNotEmpty == true)
        ? title!
        : (result.groupTitle.isNotEmpty
            ? result.groupTitle
            : (Uri.tryParse(url)?.host.isNotEmpty == true
                ? Uri.parse(url).host
                : 'Sub ${groups.length + 1}'));

    final groupId = 'sub_${DateTime.now().millisecondsSinceEpoch}';
    for (final n in result.nodes) {
      n.groupId = groupId;
      n.isFavorite = favoriteIds.contains(n.id);
    }
    final group = VpnGroup(
      id: groupId,
      title: groupTitle,
      subtitle: '${result.nodes.length} серверов',
      sourceUrl: url,
      updatedAt: DateTime.now(),
      nodes: result.nodes,
      trafficUpload:   result.userInfo['upload'],
      trafficDownload: result.userInfo['download'],
      trafficTotal:    result.userInfo['total'],
      trafficExpire:   result.userInfo['expire'],
      description:     result.announce,
    );
    groups.add(group);
    _saveGroups();
    notifyListeners();
    return null;
  }

  Future<String?> refreshSubscription(VpnGroup g) async {
    if (g.sourceUrl == null) return 'У группы нет URL подписки';
    final result = await SubscriptionLoader.load(g.sourceUrl!);
    if (result.error != null) return result.error;
    for (final n in result.nodes) {
      n.groupId = g.id;
      n.isFavorite = favoriteIds.contains(n.id);
    }
    g.nodes = result.nodes;
    g.subtitle = '${result.nodes.length} серверов';
    g.updatedAt = DateTime.now();
    if (result.userInfo.isNotEmpty) {
      g.trafficUpload   = result.userInfo['upload'];
      g.trafficDownload = result.userInfo['download'];
      g.trafficTotal    = result.userInfo['total'];
      g.trafficExpire   = result.userInfo['expire'];
    }
    if (result.announce != null) {
      g.description = result.announce;
    }
    _saveGroups();
    notifyListeners();
    return null;
  }

  void addMarketGroup({
    required int marketId,
    required String title,
    required List<VpnNode> nodes,
  }) {
    final groupId = 'market_$marketId';
    for (final n in nodes) {
      n.groupId = groupId;
      n.isFavorite = favoriteIds.contains(n.id);
    }
    final existing = groups.where((g) => g.id == groupId).cast<VpnGroup?>().firstOrNull;
    if (existing != null) {
      existing.title = title;
      existing.nodes = nodes;
      existing.subtitle = '${nodes.length} серверов · из маркета';
      existing.updatedAt = DateTime.now();
    } else {
      groups.add(VpnGroup(
        id: groupId,
        title: title,
        subtitle: '${nodes.length} серверов · из маркета',
        updatedAt: DateTime.now(),
        nodes: nodes,
      ));
    }
    _saveGroups();
    notifyListeners();
  }

  void removeGroup(String groupId) {
    groups.removeWhere((g) => g.id == groupId);
    _saveGroups();
    notifyListeners();
  }

  void renameNode(VpnNode n, String newName) {
    n.name = newName;
    if (activeNode?.id == n.id) notifyListeners();
    _saveGroups();
    notifyListeners();
  }

  void removeNode(VpnNode n) {
    if (activeNode?.id == n.id) {
      disconnect();
    }
    favoriteIds.remove(n.id);
    prefs.setStringList('favorites', favoriteIds.toList());
    for (final g in groups) {
      g.nodes.removeWhere((x) => x.id == n.id);
      g.subtitle = '${g.nodes.length} серверов';
    }
    groups.removeWhere((g) => g.nodes.isEmpty);
    _saveGroups();
    notifyListeners();
  }

  String? addManualNode(String uri) {
    final cleaned = uri.trim();
    final lower = cleaned.toLowerCase();

    
    if (lower.startsWith('tg://') ||
        lower.startsWith('https://t.me/') ||
        lower.startsWith('http://t.me/') ||
        lower.startsWith('t.me/')) {
      final proxy = MtProtoProxy.tryParse(cleaned);
      if (proxy == null) return 'Не удалось распарсить MTProto-ссылку';
      addMtProtoProxy(proxy);
      return null;
    }

    
    final node = parseUri(cleaned);
    if (node == null) return 'Не удалось распарсить URI';
    const groupId = 'manual';
    var group = groups.where((g) => g.id == groupId).cast<VpnGroup?>().firstOrNull;
    if (group == null) {
      group = VpnGroup(id: groupId, title: 'Мои серверы', nodes: []);
      groups.add(group);
    }
    if (group.nodes.any((n) => n.rawUri == node.rawUri)) {
      return 'Такой сервер уже добавлен';
    }
    node.groupId = groupId;
    node.isFavorite = favoriteIds.contains(node.id);
    group.nodes.add(node);
    group.subtitle = '${group.nodes.length} серверов';
    _saveGroups();
    notifyListeners();
    return null;
  }

  

  Timer? _pingNotifyTimer;

  Future<void> pingAll() async {
    if (_pinging) return;
    _pinging = true;
    notifyListeners();

    final allNodes = groups.expand((g) => g.nodes).toList();
    final targets = allNodes.map((n) => (host: n.address, port: n.port)).toList();

    await TcpPing.pingAll(targets, (i, ms) {
      allNodes[i].pingMs = ms;
      _pingNotifyTimer?.cancel();
      _pingNotifyTimer = Timer(const Duration(milliseconds: 500), notifyListeners);
    });

    _pingNotifyTimer?.cancel();
    _pingNotifyTimer = null;
    _pinging = false;
    notifyListeners();
  }

  Future<void> pingOne(VpnNode n) async {
    n.pingMs = await TcpPing.ping(n.address, n.port);
    notifyListeners();
  }

  

  void updateSettings(AppSettings s) {
    settings = s;
    s.save(prefs);
    notifyListeners();
    
    
    
    bridge.applyCoreConfig(s.toCoreConfig());
  }

  void _startTimer() {
    _timer?.cancel();
    connectionDuration = Duration.zero;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      connectionDuration += const Duration(seconds: 1);
      notifyListeners();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    connectionDuration = Duration.zero;
  }

  @override
  void dispose() {
    _timer?.cancel();
    bridge.dispose();
    super.dispose();
  }
}

class AppStateScope extends StatefulWidget {
  final Widget child;
  final SharedPreferences prefs;
  const AppStateScope({super.key, required this.child, required this.prefs});

  static AppState of(BuildContext context, {bool listen = true}) {
    if (listen) {
      final s = context.dependOnInheritedWidgetOfExactType<_AppStateInherited>();
      assert(s != null, 'AppStateScope not found');
      return s!.state;
    } else {
      final s = context.getInheritedWidgetOfExactType<_AppStateInherited>();
      assert(s != null, 'AppStateScope not found');
      return s!.state;
    }
  }

  @override
  State<AppStateScope> createState() => _AppStateScopeState();
}

class _AppStateScopeState extends State<AppStateScope> {
  late AppState _state;

  @override
  void initState() {
    super.initState();
    _state = AppState(widget.prefs);
    _state.addListener(_onChange);
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    _state.removeListener(_onChange);
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AppStateInherited(state: _state, child: widget.child);
  }
}

class _AppStateInherited extends InheritedWidget {
  final AppState state;
  const _AppStateInherited({required this.state, required super.child});

  @override
  bool updateShouldNotify(_AppStateInherited oldWidget) => true;
}

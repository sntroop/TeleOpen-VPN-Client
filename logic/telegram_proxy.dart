import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/mtproto_proxy.dart';
import 'ping.dart';

class TelegramClient {
  final String packageName;
  final String appName;

  
  final Uint8List? icon;

  const TelegramClient({
    required this.packageName,
    required this.appName,
    this.icon,
  });
}

const _knownTelegramPackages = <String>{
  'org.telegram.messenger',          
  'org.telegram.messenger.web',      
  'org.telegram.messenger.beta',     
  'org.thunderdog.challegram',       
  'org.telegram.plus',               
  'com.exteragram.messenger',        
  'app.nicegram',                    
  'ru.nekogram.app',                 
  'tw.nekomimi.nekogram',            
  'org.forkgram.messenger',          
  'org.telegram.AyuGram',            
  'com.cutegram.app',                
  'org.telegram.messenger.beta.web', 
  'uz.unnarsx.cherrygram',           
};

class TelegramProxyService {
  
  
  
  
  static Future<List<TelegramClient>> detectClients() async {
    if (!Platform.isAndroid) return const [];

    final List<AppInfo> apps;
    try {
      
      apps = await InstalledApps.getInstalledApps(true, false, '');
    } catch (_) {
      return const [];
    }

    final clients = <TelegramClient>[];
    for (final a in apps) {
      final pkg = a.packageName;
      final name = a.name;
      if (_looksLikeTelegram(pkg, name)) {
        clients.add(TelegramClient(
          packageName: pkg,
          appName: name.isNotEmpty ? name : pkg,
          icon: a.icon,
        ));
      }
    }

    
    final seen = <String>{};
    final unique = clients.where((c) => seen.add(c.packageName)).toList();

    unique.sort((a, b) {
      final aOfficial = a.packageName == 'org.telegram.messenger';
      final bOfficial = b.packageName == 'org.telegram.messenger';
      if (aOfficial && !bOfficial) return -1;
      if (!aOfficial && bOfficial) return 1;
      return a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
    });

    return unique;
  }

  
  static bool _looksLikeTelegram(String pkg, String name) {
    if (_knownTelegramPackages.contains(pkg)) return true;

    final p = pkg.toLowerCase();
    final n = name.toLowerCase();

    
    final pkgHit = p.contains('telegram') ||
        p.contains('challegram') ||
        p.contains('nekogram') ||
        p.contains('exteragram') ||
        p.contains('forkgram') ||
        p.contains('cherrygram') ||
        p.contains('ayugram') ||
        p.endsWith('.gram');

    
    final nameHit = n.contains('telegram') || n.endsWith('gram');

    return pkgHit || nameHit;
  }

  
  
  
  
  static Future<void> openInClient(
    MtProtoProxy proxy,
    String packageName,
  ) async {
    final link = proxy.buildLink(); 

    if (!Platform.isAndroid) {
      
      await _launchSystem(link);
      return;
    }

    try {
      
      
      await _channel.invokeMethod<void>('openProxyInApp', {
        'url': link,
        'package': packageName,
      });
    } on PlatformException catch (e) {
      throw MtProtoProxyException(
        'Не удалось открыть ${proxy.kind.label} в приложении: ${e.message}',
      );
    } on MissingPluginException {
      
      
      await _launchSystem(link);
    }
  }

  
  
  static Future<void> openWithSystemChooser(MtProtoProxy proxy) async {
    final link = proxy.buildLink();
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('openProxyChooser', {'url': link});
        return;
      } on PlatformException catch (_) {
        
      } on MissingPluginException catch (_) {
        
      }
    }
    await _launchSystem(link);
  }

  
  
  static const _channel = MethodChannel('com.example.my_vpn/native');

  static Future<void> _launchSystem(String link) async {
    final uri = Uri.parse(link);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      throw MtProtoProxyException(
        'Не найдено приложение для открытия Telegram-ссылки. '
        'Установите Telegram или один из его форков.',
      );
    }
  }
}

class MtProtoProxyPinger {
  
  static Future<int?> pingOne(MtProtoProxy proxy) async {
    final ms = await TcpPing.ping(proxy.server, proxy.port);
    proxy.pingMs = ms;
    return ms;
  }

  
  
  static Future<void> pingAll(
    List<MtProtoProxy> proxies, {
    void Function(int index, int? ms)? onResult,
    int concurrency = 8,
  }) async {
    final targets = proxies
        .map((p) => (host: p.server, port: p.port))
        .toList();
    await TcpPing.pingAll(
      targets,
      (i, ms) {
        proxies[i].pingMs = ms;
        onResult?.call(i, ms);
      },
      concurrency: concurrency,
    );
  }
}

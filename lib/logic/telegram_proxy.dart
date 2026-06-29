// lib/logic/telegram_proxy.dart
//
// Обнаружение установленных Telegram-клиентов (официальный + форки) и
// запуск deep-link установки MTProto Proxy в выбранном клиенте.
//
// Как это работает:
//   1. MtProtoProxy.buildLink() даёт ссылку tg://proxy?server=&port=&secret=
//   2. Мы находим установленные приложения, которые умеют её открывать —
//      это все Telegram-форки (они регистрируют intent-filter на tg://).
//   3. Пользователь выбирает форк → мы запускаем Intent.ACTION_VIEW c
//      явно указанным package этого форка.
//   4. Telegram сам показывает штатное окно «Подключить прокси».
//
// Системный chooser (без указания package) используется как fallback,
// если форков не нашлось или платформа не Android.

import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/mtproto_proxy.dart';
import 'ping.dart';

/// Один установленный Telegram-клиент.
class TelegramClient {
  final String packageName;
  final String appName;

  /// Иконка приложения (PNG-байты). null если не удалось получить.
  final Uint8List? icon;

  const TelegramClient({
    required this.packageName,
    required this.appName,
    this.icon,
  });
}

/// Известные package'и Telegram и популярных форков.
///
/// Список нужен только для надёжного определения «это Telegram-клиент».
/// Полагаться только на него нельзя — форков много и появляются новые,
/// поэтому в detectClients() есть и эвристика по имени пакета/приложения.
const _knownTelegramPackages = <String>{
  'org.telegram.messenger',          // Telegram (официальный, Play Store)
  'org.telegram.messenger.web',      // Telegram (официальный, сайт/APK)
  'org.telegram.messenger.beta',     // Telegram Beta
  'org.thunderdog.challegram',       // Telegram X
  'org.telegram.plus',               // Plus Messenger
  'com.exteragram.messenger',        // exteraGram
  'app.nicegram',                    // Nicegram
  'ru.nekogram.app',                 // Nekogram (вариант package)
  'tw.nekomimi.nekogram',            // Nekogram X
  'org.forkgram.messenger',          // Forkgram
  'org.telegram.AyuGram',            // AyuGram
  'com.cutegram.app',                // CuteGram
  'org.telegram.messenger.beta.web', // редкий beta-вариант
  'uz.unnarsx.cherrygram',           // Cherrygram
};

class TelegramProxyService {
  /// Находит установленные Telegram-клиенты.
  ///
  /// Возвращает пустой список не-Android платформах или если ничего не
  /// установлено. Сортировка: официальный Telegram первым, далее по имени.
  static Future<List<TelegramClient>> detectClients() async {
    if (!Platform.isAndroid) return const [];

    final List<AppInfo> apps;
    try {
      // (withIcon: true, includeSystemApps: false, packageNamePrefix: '')
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

    // дедуп по packageName
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

  /// Эвристика: похоже ли приложение на Telegram-клиент.
  static bool _looksLikeTelegram(String pkg, String name) {
    if (_knownTelegramPackages.contains(pkg)) return true;

    final p = pkg.toLowerCase();
    final n = name.toLowerCase();

    // package'и форков почти всегда содержат telegram/gram/nekox и т.п.
    final pkgHit = p.contains('telegram') ||
        p.contains('challegram') ||
        p.contains('nekogram') ||
        p.contains('exteragram') ||
        p.contains('forkgram') ||
        p.contains('cherrygram') ||
        p.contains('ayugram') ||
        p.endsWith('.gram');

    // имя приложения тоже часто содержит "gram"
    final nameHit = n.contains('telegram') || n.endsWith('gram');

    return pkgHit || nameHit;
  }

  /// Открывает deep-link установки прокси в КОНКРЕТНОМ клиенте.
  ///
  /// Бросает [MtProtoProxyException] если запуск не удался (клиент не
  /// обработал ссылку — например, юзер только что удалил приложение).
  static Future<void> openInClient(
    MtProtoProxy proxy,
    String packageName,
  ) async {
    final link = proxy.buildLink(); // tg://proxy?...

    if (!Platform.isAndroid) {
      // На не-Android просто пытаемся открыть ссылку системой.
      await _launchSystem(link);
      return;
    }

    try {
      // Запускаем ACTION_VIEW с явным package — Android отдаст ссылку
      // именно этому форку, без диалога выбора.
      await _channel.invokeMethod<void>('openProxyInApp', {
        'url': link,
        'package': packageName,
      });
    } on PlatformException catch (e) {
      throw MtProtoProxyException(
        'Не удалось открыть ${proxy.kind.label} в приложении: ${e.message}',
      );
    } on MissingPluginException {
      // Нативный метод не подключён (например забыли MainActivity-часть) —
      // деградируем до системного открытия.
      await _launchSystem(link);
    }
  }

  /// Открывает deep-link через системный chooser Android («Открыть с
  /// помощью…»). Используется как fallback и как явный выбор юзера.
  static Future<void> openWithSystemChooser(MtProtoProxy proxy) async {
    final link = proxy.buildLink();
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('openProxyChooser', {'url': link});
        return;
      } on PlatformException catch (_) {
        // упадём в _launchSystem ниже
      } on MissingPluginException catch (_) {
        // упадём в _launchSystem ниже
      }
    }
    await _launchSystem(link);
  }

  // Используем тот же нативный канал, что и VPN-движок (см. MainActivity.kt:
  // METHOD_CHANNEL). Отдельный канал плодить не нужно.
  static const _channel = MethodChannel('space.teleopen.app/native');

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

// ════════════════════════════════════════════════════════════════════════════
// ПИНГ MTProto-прокси
//
// MTProto-прокси пингуется не как VLESS — у него нет нашего хендшейка.
// Меряем TCP-коннект до server:port: это показывает доступность прокси и
// сетевую задержку до него. Используем тот же TcpPing, что и VPN-узлы.
// ════════════════════════════════════════════════════════════════════════════

class MtProtoProxyPinger {
  /// Пингует один прокси, записывает результат в proxy.pingMs.
  static Future<int?> pingOne(MtProtoProxy proxy) async {
    final ms = await TcpPing.ping(proxy.server, proxy.port);
    proxy.pingMs = ms;
    return ms;
  }

  /// Пингует список прокси параллельно. onResult вызывается по мере
  /// готовности каждого (index — позиция в исходном списке).
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

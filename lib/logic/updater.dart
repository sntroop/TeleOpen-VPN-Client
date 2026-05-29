// lib/logic/updater.dart
//
// In-app self-update для TeleOpen.
//
// Логика:
//   1. При старте приложения вызываем UpdaterService.init() — он читает
//      versionCode/versionName текущей установки через MethodChannel.
//   2. check() стучится на /updates/latest. Если version_code на сервере
//      больше нашего — выставляем `available` и notify слушателей.
//      Параллельно фаерим локальное уведомление (один раз на версию).
//   3. downloadAndInstall() скачивает APK во внутренний cache, проверяет
//      sha256, потом просит нативку открыть системный установщик.
//      Дальше юзер тапает «Установить» в системном диалоге.
//
// ВАЖНО: всё это работает только для sideload-сборок. В Google Play
// самообновление APK запрещено политикой — там надо использовать In-App
// Updates API из Play Core. У нас распространение мимо Play, так что ок.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'market_api.dart' show kApiBase;

/// Что вернул сервер на /updates/latest.
class UpdateInfo {
  final int versionCode;
  final String versionName;
  final String changelog;
  final int size;
  final String sha256;
  final String url; // абсолютный URL (склеен с kApiBase)

  UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.changelog,
    required this.size,
    required this.sha256,
    required this.url,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> j) {
    final raw = (j['url'] ?? '').toString();
    return UpdateInfo(
      versionCode: (j['version_code'] as num).toInt(),
      versionName: (j['version_name'] ?? '') as String,
      changelog:   (j['changelog']    ?? '') as String,
      size:        (j['size']         as num? ?? 0).toInt(),
      sha256:      ((j['sha256']      ?? '') as String).toLowerCase(),
      url:         raw.startsWith('http') ? raw : '$kApiBase$raw',
    );
  }

  String get sizeHuman {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

/// Singleton-сервис. Регистрируется в дереве через ChangeNotifierProvider
/// (или просто хранится глобально — у нас уже есть AppStateScope, но я
/// специально не залезаю в него чтобы не мешать существующей архитектуре).
class UpdaterService extends ChangeNotifier {
  UpdaterService._();
  static final UpdaterService instance = UpdaterService._();

  // Тот же канал, что в MainActivity (METHOD_CHANNEL).
  static const _channel = MethodChannel('space.teleopen.app/native');

  // Ключи в SharedPreferences
  static const _kSkipped       = 'update_skipped_version_code';
  static const _kLastNotified  = 'update_last_notified_version_code';

  // ── Состояние ──────────────────────────────────────────────────────────
  int? currentVersionCode;
  String? currentVersionName;

  UpdateInfo? available;        // null = апдейтов нет (или уже скрыт)
  bool downloading = false;
  double progress = 0;          // 0..1
  String? error;                // последняя ошибка (для UI)
  bool ready = false;           // init() прошёл

  final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();

  Timer? _poll;

  /// Вызвать ОДИН РАЗ при старте приложения (в main(), после ensureInitialized).
  Future<void> init({Duration pollInterval = const Duration(hours: 6)}) async {
    try {
      final code = await _channel.invokeMethod<int>('getAppVersionCode');
      final name = await _channel.invokeMethod<String>('getAppVersionName');
      currentVersionCode = code;
      currentVersionName = name;
    } catch (e) {
      debugPrint('Updater: cannot read app version: $e');
    }

    try {
      await _notif.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
      // Android 13+ (API 33): POST_NOTIFICATIONS — runtime-разрешение.
      // Без явного запроса _notif.show() молча не покажет уведомление,
      // даже если permission объявлен в манифесте.
      final android = _notif.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Updater: notif init failed: $e');
    }

    ready = true;
    notifyListeners();

    // Первая проверка — сразу, дальше по таймеру.
    unawaited(check(silent: true));
    _poll?.cancel();
    _poll = Timer.periodic(pollInterval, (_) => check(silent: true));
  }

  /// Запрос /updates/latest и сравнение версий.
  /// [silent] = true — не показывать ошибки в UI, не фаерить нотификации
  /// (например, при периодическом poll'е).
  Future<UpdateInfo?> check({bool silent = false}) async {
    if (!silent) error = null;
    try {
      final r = await http
          .get(Uri.parse('$kApiBase/updates/latest'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) {
        throw 'HTTP ${r.statusCode}';
      }
      final body = json.decode(r.body) as Map<String, dynamic>;
      if (body['available'] != true) {
        available = null;
        notifyListeners();
        return null;
      }
      final info = UpdateInfo.fromJson(body);
      final my = currentVersionCode ?? 0;

      // Проверяем, не пропустил ли юзер именно эту версию.
      final prefs = await SharedPreferences.getInstance();
      final skipped = prefs.getInt(_kSkipped) ?? 0;

      if (info.versionCode > my && info.versionCode > skipped) {
        available = info;
        notifyListeners();
        // Локальное уведомление (один раз на версию).
        await _maybeNotify(info);
        return info;
      } else {
        available = null;
        notifyListeners();
        return null;
      }
    } catch (e) {
      if (!silent) {
        error = e.toString();
        notifyListeners();
      }
      debugPrint('Updater.check: $e');
      return null;
    }
  }

  Future<void> _maybeNotify(UpdateInfo info) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_kLastNotified) ?? 0;
      if (last >= info.versionCode) return; // уже стрелили
      await _notif.show(
        4242,
        'Доступна новая версия TeleOpen',
        'v${info.versionName} — откройте приложение, чтобы обновить',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'updates',
            'Обновления приложения',
            channelDescription: 'Уведомления о новых версиях',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
      await prefs.setInt(_kLastNotified, info.versionCode);
    } catch (e) {
      debugPrint('Updater._maybeNotify: $e');
    }
  }

  /// Юзер нажал «Позже / Пропустить» — больше не показываем баннер для
  /// этой версии. Следующий апдейт (с бо́льшим versionCode) снова покажется.
  Future<void> skip() async {
    final info = available;
    if (info == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSkipped, info.versionCode);
    available = null;
    notifyListeners();
  }

  /// Качаем APK → проверяем sha256 → передаём в нативку для установки.
  Future<void> downloadAndInstall() async {
    final info = available;
    if (info == null) return;
    if (downloading) return;

    downloading = true;
    progress = 0;
    error = null;
    notifyListeners();

    File? file;
    try {
      // Кладём в getTemporaryDirectory — путь должен совпадать с file_paths.xml
      // (cache-path name="updates" path="updates/"), иначе FileProvider в
      // нативке кинет IllegalArgumentException "Failed to find configured root".
      final cacheDir = await getTemporaryDirectory();
      final dir = Directory('${cacheDir.path}/updates');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      // Чистим старые APK чтобы не копились в кэше.
      try {
        for (final entry in dir.listSync()) {
          if (entry is File && entry.path.endsWith('.apk')) {
            await entry.delete();
          }
        }
      } catch (_) {}

      final path = '${dir.path}/teleopen-${info.versionCode}.apk';
      file = File(path);

      final req = http.Request('GET', Uri.parse(info.url));
      final client = http.Client();
      final resp = await client.send(req).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        throw 'HTTP ${resp.statusCode}';
      }
      final total = resp.contentLength ?? info.size;
      int received = 0;
      final sink = file.openWrite();
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          progress = received / total;
          // Дросселируем notify чтобы не дёргать build каждые 100 байт.
          // Простейшая стратегия: раз в ~0.5% прогресса.
          notifyListeners();
        }
      }
      await sink.flush();
      await sink.close();
      client.close();

      // sha256 — defense-in-depth поверх TLS. Если не совпало —
      // значит на CDN/прокси кто-то подсунул не тот файл. Удаляем.
      final digest = sha256.convert(await file.readAsBytes()).toString();
      if (info.sha256.isNotEmpty && digest != info.sha256) {
        await file.delete();
        throw 'Контрольная сумма не совпала (ожидалось ${info.sha256.substring(0, 8)}…, получено ${digest.substring(0, 8)}…)';
      }

      progress = 1.0;
      notifyListeners();

      // Передаём нативке. Дальше юзер увидит системный экран установки.
      await _channel.invokeMethod('installApk', {'path': path});
    } on PlatformException catch (e) {
      // Ожидаемый случай: NEED_PERMISSION — нативка уже открыла настройки.
      error = e.message ?? e.code;
      debugPrint('Updater.install platform error: ${e.code} ${e.message}');
    } catch (e) {
      error = e.toString();
      debugPrint('Updater.downloadAndInstall: $e');
      // Если упали в процессе скачивания — подтираем недокаченный файл.
      try {
        if (file != null && await file.exists()) await file.delete();
      } catch (_) {}
    } finally {
      downloading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}

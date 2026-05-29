// lib/logic/hysteria2.dart
//
// Менеджер процесса hysteria2: запускает нативный бинарник на 127.0.0.1:10900
// (SOCKS5), потом TUN VpnService форвардит трафик через этот порт.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'crash_log.dart';

class Hysteria2Manager {
  static Process? _process;
  static String? lastServer;
  static const int socks5Port = 10900;

  // true, если запущенный бинарь уже завершился (упал или его убили).
  static bool _exited = false;

  static bool get isRunning => _process != null && !_exited;

  static Future<bool> start(String hy2Uri) async {
    await stop();
    try {
      const platform = MethodChannel('space.teleopen.app/native');
      final nativeLibDir = await platform.invokeMethod<String>('getNativeLibDir');
      if (nativeLibDir == null) return false;
      final binPath = '$nativeLibDir/libhysteria2.so';

      // Парсим URI
      final clean = hy2Uri.contains('#')
          ? hy2Uri.substring(0, hy2Uri.indexOf('#'))
          : hy2Uri;
      final schemeIdx = clean.indexOf('://');
      if (schemeIdx < 0) return false;
      final withoutScheme = clean.substring(schemeIdx + 3);

      final atIdx = withoutScheme.lastIndexOf('@');
      final password = atIdx >= 0
          ? Uri.decodeComponent(withoutScheme.substring(0, atIdx))
          : '';
      final afterAt = atIdx >= 0 ? withoutScheme.substring(atIdx + 1) : withoutScheme;

      final qIdx = afterAt.indexOf('?');
      final hostPort = qIdx >= 0 ? afterAt.substring(0, qIdx) : afterAt;
      final paramStr = qIdx >= 0 ? afterAt.substring(qIdx + 1) : '';

      final colonIdx = hostPort.lastIndexOf(':');
      final host = colonIdx >= 0 ? hostPort.substring(0, colonIdx) : hostPort;
      final port = colonIdx >= 0 ? hostPort.substring(colonIdx + 1) : '443';

      final params = <String, String>{};
      for (final p in paramStr.split('&')) {
        final kv = p.split('=');
        if (kv.length == 2) params[kv[0]] = Uri.decodeComponent(kv[1]);
      }

      final sni = params['sni'] ?? host;
      final insecure = params['insecure'] == '1';
      final obfsPassword = params['obfs-password'] ?? '';

      final configDir = await getApplicationSupportDirectory();
      final configFile = File('${configDir.path}/hy2_config.json');
      final hy2Config = <String, dynamic>{
        'server': '$host:$port',
        'auth': password,
        'socks5': {'listen': '0.0.0.0:$socks5Port'},
        'tls': {'sni': sni, 'insecure': insecure},
      };
      if (obfsPassword.isNotEmpty) {
        hy2Config['obfs'] = {
          'type': 'salamander',
          'salamander': {'password': obfsPassword},
        };
      }
      await configFile.writeAsString(jsonEncode(hy2Config));
      lastServer = '$host:$port';

      _exited = false;
      _process = await Process.start(binPath, ['-c', configFile.path]);
      // Фиксируем факт завершения процесса, чтобы start() мог понять,
      // что бинарь упал сразу, а isRunning не врал.
      final startedProc = _process!;
      startedProc.exitCode.then((code) {
        _exited = true;
        CrashLog.note('hy2/exit', 'hysteria2 завершился, exitCode=$code');
        if (identical(_process, startedProc)) _process = null;
      });
      _process!.stdout
          .transform(const SystemEncoding().decoder)
          .listen((line) {
        if (line.trim().isNotEmpty) CrashLog.note('hy2/stdout', line.trim());
      });
      // stderr хистерии — главный диагностический источник. Раньше
      // отбрасывался (.listen((_) {})), поэтому причина падений бинаря
      // была не видна. Теперь пишем в CrashLog.
      _process!.stderr
          .transform(const SystemEncoding().decoder)
          .listen((line) {
        if (line.trim().isNotEmpty) CrashLog.note('hy2/stderr', line.trim());
      });

      // Бинарь мог упасть сразу (плохой конфиг, занятый порт) — проверяем,
      // что процесс ещё жив после паузы на подъём.
      await Future.delayed(const Duration(milliseconds: 1500));
      if (_exited) {
        CrashLog.note('hy2/start', 'процесс завершился сразу после запуска');
        _process = null;
        return false;
      }
      CrashLog.note('hy2/start', 'hysteria2 поднят, server=$lastServer');
      return true;
    } catch (e, st) {
      CrashLog.note('hy2/start', 'НЕ удалось запустить: $e\n$st');
      _process = null;
      return false;
    }
  }

  static Future<void> stop() async {
    final p = _process;
    if (p != null) {
      try {
        p.kill(ProcessSignal.sigterm);
      } catch (e) {
        CrashLog.note('hy2/stop', 'kill не удался: $e');
      }
    }
    _process = null;
    _exited = true;
  }
}

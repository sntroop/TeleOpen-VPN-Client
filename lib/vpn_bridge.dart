import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Снапшот текущей статистики туннеля.
class VpnStats {
  final int rxBytes;
  final int txBytes;
  final int rxRate; // байт/сек
  final int txRate;
  final int uptimeMs;
  const VpnStats({
    required this.rxBytes,
    required this.txBytes,
    required this.rxRate,
    required this.txRate,
    required this.uptimeMs,
  });
  static const zero = VpnStats(rxBytes: 0, txBytes: 0, rxRate: 0, txRate: 0, uptimeMs: 0);
}

class VpnBridge {
  static const _method = MethodChannel('com.example.my_vpn/native');
  static const _event  = EventChannel('com.example.my_vpn/vpn_status');

  StreamSubscription? _statusSub;
  void Function(String status)? _onStatus;
  void Function(VpnStats stats)? _onStats;

  Future<void> init({
    required void Function(String status) onStatus,
    void Function(VpnStats stats)? onStats,
  }) async {
    _onStatus = onStatus;
    _onStats = onStats;
    _statusSub?.cancel();
    _statusSub = _event.receiveBroadcastStream().listen(
      (dynamic event) {
        // ВАЖНО: всё тело колбэка обёрнуто в try/catch.
        // Исключение, брошенное здесь, НЕ ловится `onError` ниже
        // (onError ловит только ошибки самого стрима), а становится
        // необработанным и роняет изолят целиком — то есть приложение
        // крашится без видимого лога. Поэтому ловим всё сами.
        try {
          // EventChannel на Android может присылать события РАЗНЫХ типов:
          // обычную строку (статус), JSON-строку или сразу Map/словарь
          // (если натив вызвал eventSink.success(hashMapOf(...))).
          // Старый код делал `event as String?` и падал на Map.

          // 1) Событие пришло уже готовым словарём — это статистика.
          if (event is Map) {
            final m = event.cast<String, dynamic>();
            if (m['type'] == 'stats') {
              _emitStats(m);
              return;
            }
            // словарь без type=stats — пробуем достать статус
            final s = (m['status'] ?? m['state'] ?? '').toString();
            if (s.isNotEmpty) {
              debugPrint('=== VpnBridge status (map): ${s.toUpperCase()}');
              _onStatus?.call(s.toUpperCase());
            }
            return;
          }

          // 2) Иначе приводим к строке безопасно (не через `as`).
          final raw = event?.toString() ?? '';
          if (raw.isEmpty) return;

          // JSON-кадр (статистика) vs обычная строка (статус)
          if (raw.startsWith('{')) {
            try {
              final decoded = jsonDecode(raw);
              if (decoded is Map) {
                final m = decoded.cast<String, dynamic>();
                if (m['type'] == 'stats') {
                  _emitStats(m);
                  return;
                }
              }
            } catch (e) {
              debugPrint('=== VpnBridge bad stats frame: $e');
              // не статистика — провалимся ниже и обработаем как статус
            }
          }

          final status = raw.toUpperCase();
          debugPrint('=== VpnBridge status: $status');
          _onStatus?.call(status);
        } catch (e, st) {
          // Любая неожиданная ошибка обработки события не должна
          // ронять приложение. Просто логируем.
          debugPrint('=== VpnBridge event handler error: $e\n$st');
        }
      },
      onError: (e) {
        debugPrint('=== VpnBridge error: $e');
        _onStatus?.call('STOPPED');
      },
    );
  }

  /// Запустить hysteria2 → TUN (через tun2socks).
  /// Если perAppEnabled и список не пуст — через VPN пойдут ТОЛЬКО эти пакеты.
  Future<bool> start({
    int socks5Port = 10900,
    String remark = 'TeleOpen',
    bool perAppEnabled = false,
    List<String> allowedPackages = const [],
  }) async {
    try {
      await _method.invokeMethod('startVpn', {
        'socks5Port': socks5Port,
        'remark': remark,
        'perAppEnabled': perAppEnabled,
        'allowedPackages': allowedPackages,
      });
      return true;
    } on PlatformException catch (e) {
      debugPrint('=== VPN start error: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('=== VPN start error: $e');
      return false;
    }
  }

  /// Запустить vless/vmess/trojan → TUN (через V2RayPoint xray)
  Future<bool> startV2Ray({
    required String config,
    required String remark,
    bool perAppEnabled = false,
    List<String> allowedPackages = const [],
  }) async {
    try {
      await _method.invokeMethod('startV2RayVpn', {
        'config': config,
        'remark': remark,
        'perAppEnabled': perAppEnabled,
        'allowedPackages': allowedPackages,
      });
      return true;
    } on PlatformException catch (e) {
      debugPrint('=== V2Ray VPN start error: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('=== V2Ray VPN start error: $e');
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _method.invokeMethod('stopVpn');
    } catch (e) {
      debugPrint('=== VPN stop error: $e');
    }
  }

  Future<String?> getNativeLibDir() async {
    try {
      return await _method.invokeMethod<String>('getNativeLibDir');
    } catch (_) {
      return null;
    }
  }

  /// Прочитать debug-лог VPN-сервиса (последние ~50КБ)
  Future<String> getVpnLog() async {
    try {
      return await _method.invokeMethod<String>('getVpnLog') ?? '(лог пустой)';
    } catch (e) {
      return 'Ошибка чтения лога: $e';
    }
  }

  /// Очистить debug-лог VPN-сервиса
  Future<void> clearVpnLog() async {
    try {
      await _method.invokeMethod('clearVpnLog');
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Расширения для mihomo / clash.meta
  // ═══════════════════════════════════════════════════════════════════════

  /// Передать актуальный набор настроек в нативный слой.
  /// Натив (Android Service / iOS NEPacketTunnelProvider) на своей стороне
  /// конвертирует ключи в YAML-секции mihomo и:
  ///   - либо обновляет конфиг на лету (через clash REST-API),
  ///   - либо помечает, что нужен рестарт ядра при следующем start*().
  Future<bool> applyCoreConfig(Map<String, dynamic> config) async {
    try {
      await _method.invokeMethod('applyCoreConfig', {'config': config});
      return true;
    } on PlatformException catch (e) {
      debugPrint('=== applyCoreConfig error: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('=== applyCoreConfig error: $e');
      return false;
    }
  }

  /// Импорт geo-файла. [kind] = 'geoip' | 'geosite' | 'country' | 'asn',
  /// [sourcePath] — путь во временной директории (после file_picker).
  /// Натив копирует файл в каталог приложения и возвращает финальный путь,
  /// который сохраняется в AppSettings.
  Future<String?> importGeoFile({
    required String kind,
    required String sourcePath,
  }) async {
    try {
      final res = await _method.invokeMethod<String>('importGeoFile', {
        'kind': kind,
        'sourcePath': sourcePath,
      });
      return res;
    } catch (e) {
      debugPrint('=== importGeoFile error: $e');
      return null;
    }
  }

  /// Запустить DNS leak test. Натив делает несколько DoH-запросов к
  /// whoami-сервисам (resolver.dnscrypt.info / whoami.akamai.net) и
  /// возвращает уникальный список резолверов.
  ///
  /// Структура ответа:
  ///   [{ ip: '1.1.1.1', org: 'Cloudflare', country: 'US', leak: false }, ...]
  Future<List<Map<String, dynamic>>> runDnsLeakTest() async {
    try {
      final res = await _method.invokeMethod<List<dynamic>>('runDnsLeakTest');
      if (res == null) return const [];
      return res
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    } catch (e) {
      debugPrint('=== runDnsLeakTest error: $e');
      return const [];
    }
  }

  /// Запустить проверку заметности прокси.
  ///
  /// Структура ответа:
  ///   [{ id: 'webrtc', ok: true, detail: '...' }, ...]
  Future<List<Map<String, dynamic>>> runProxyVisibilityCheck() async {
    try {
      final res = await _method.invokeMethod<List<dynamic>>('runProxyVisibilityCheck');
      if (res == null) return const [];
      return res
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    } catch (e) {
      debugPrint('=== runProxyVisibilityCheck error: $e');
      return const [];
    }
  }

  /// Безопасно собирает VpnStats из произвольного словаря (значения
  /// могут прийти как num, String или null — всё приводим аккуратно).
  void _emitStats(Map<String, dynamic> m) {
    int pick(String key) {
      final v = m[key];
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    _onStats?.call(VpnStats(
      rxBytes:  pick('rx'),
      txBytes:  pick('tx'),
      rxRate:   pick('rxRate'),
      txRate:   pick('txRate'),
      uptimeMs: pick('uptimeMs'),
    ));
  }

  void dispose() {
    _statusSub?.cancel();
    _statusSub = null;
  }
}

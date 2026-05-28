import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VpnStats {
  final int rxBytes;
  final int txBytes;
  final int rxRate; 
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
        
        
        
        
        
        try {
          
          
          
          

          
          if (event is Map) {
            final m = event.cast<String, dynamic>();
            if (m['type'] == 'stats') {
              _emitStats(m);
              return;
            }
            
            final s = (m['status'] ?? m['state'] ?? '').toString();
            if (s.isNotEmpty) {
              debugPrint('=== VpnBridge status (map): ${s.toUpperCase()}');
              _onStatus?.call(s.toUpperCase());
            }
            return;
          }

          
          final raw = event?.toString() ?? '';
          if (raw.isEmpty) return;

          
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
              
            }
          }

          final status = raw.toUpperCase();
          debugPrint('=== VpnBridge status: $status');
          _onStatus?.call(status);
        } catch (e, st) {
          
          
          debugPrint('=== VpnBridge event handler error: $e\n$st');
        }
      },
      onError: (e) {
        debugPrint('=== VpnBridge error: $e');
        _onStatus?.call('STOPPED');
      },
    );
  }

  
  
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

  
  Future<String> getVpnLog() async {
    try {
      return await _method.invokeMethod<String>('getVpnLog') ?? '(лог пустой)';
    } catch (e) {
      return 'Ошибка чтения лога: $e';
    }
  }

  
  Future<void> clearVpnLog() async {
    try {
      await _method.invokeMethod('clearVpnLog');
    } catch (_) {}
  }

  
  
  

  
  
  
  
  
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

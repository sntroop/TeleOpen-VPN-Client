// lib/state/app_state_ping.dart
//
// Пинг нод (все сразу / одна). Режим берётся из AppSettings.pingMode:
//   TCP  — TcpPing.ping (handshake);
//   UDP  — TcpPing.pingUdp (датаграмм-зонд, best-effort);
//   HTTP — реальная задержка через ядро (bridge.measureDelay по конфигу ноды).
// part of app_state.

part of 'app_state.dart';

mixin AppStatePing on AppStateBase {
  // HTTP-режим поднимает временный инстанс ядра на ноду — это тяжелее
  // TCP/UDP, поэтому параллелим осторожнее.
  static const int _httpConcurrency = 4;

  Future<void> pingAll() async {
    if (_pinging) return;
    _pinging = true;
    notifyListeners();

    final allNodes = groups.expand((g) => g.nodes).toList();

    void onResult(int i, int? ms) {
      allNodes[i].pingMs = ms;
      _pingNotifyTimer?.cancel();
      _pingNotifyTimer = Timer(const Duration(milliseconds: 500), notifyListeners);
    }

    if (settings.pingMode == 'HTTP') {
      await _measureHttpAll(allNodes, onResult);
    } else {
      final targets = allNodes.map((n) => (host: n.address, port: n.port)).toList();
      await TcpPing.pingAll(targets, onResult, udp: settings.pingMode == 'UDP');
    }

    _pingNotifyTimer?.cancel();
    _pingNotifyTimer = null;
    _pinging = false;
    notifyListeners();
  }

  Future<void> pingOne(VpnNode n) async {
    n.pingMs = await _pingNode(n);
    notifyListeners();
  }

  /// Пинг одной ноды согласно текущему режиму.
  Future<int?> _pingNode(VpnNode n) async {
    switch (settings.pingMode) {
      case 'HTTP':
        return _measureHttp(n);
      case 'UDP':
        return TcpPing.pingUdp(n.address, n.port);
      default:
        return TcpPing.ping(n.address, n.port);
    }
  }

  /// Реальная задержка через ядро. Для hysteria2 (отдельный движок, конфиг
  /// xray не строится) и при ошибке сборки — откатываемся на TCP-handshake.
  Future<int?> _measureHttp(VpnNode n) async {
    if (n.protocol == VpnProtocol.hysteria2) {
      return TcpPing.ping(n.address, n.port);
    }
    try {
      final cfg = buildXrayConfig(
        n,
        useMux: settings.useMux,
        resolveDestination: settings.resolveDestination,
      );
      return await bridge.measureDelay(config: cfg);
    } catch (_) {
      return TcpPing.ping(n.address, n.port);
    }
  }

  Future<void> _measureHttpAll(
    List<VpnNode> nodes,
    void Function(int index, int? ms) onResult,
  ) async {
    int next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= nodes.length) return;
        onResult(i, await _measureHttp(nodes[i]));
      }
    }
    await Future.wait(List.generate(_httpConcurrency, (_) => worker()));
  }
}

// lib/state/app_state_connection.dart
//
// Подключение/отключение туннеля (Hysteria2 либо xray), выбор активной ноды,
// запись истории сессий. part of app_state.

part of 'app_state.dart';

mixin AppStateConnection on AppStateBase {
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
      // Per-app proxy — берём общий список (если включено)
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

  @override
  Future<void> disconnect() async {
    // Сохраняем сессию ДО обнуления activeNode
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
        // ignore: discarded_futures
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
}

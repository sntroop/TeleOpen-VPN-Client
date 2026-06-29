// lib/state/app_state_connection.dart
//
// Подключение/отключение туннеля (Hysteria2 либо xray), выбор активной ноды,
// запись истории сессий. part of app_state.

part of 'app_state.dart';

mixin AppStateConnection on AppStateBase {
  @override
  Future<void> connect(VpnNode node) async {
    if (status == VpnStatus.connecting) return;
    if (status == VpnStatus.connected) {
      await disconnect();
      await Future.delayed(const Duration(milliseconds: 300));
    }
    // Пользователь (или авто-старт) инициирует коннект → снимаем флаг userStop,
    // чтобы failover снова мог срабатывать на обрывах этой сессии.
    _failover.userStopped = false;
    activeNode = node;
    status = VpnStatus.connecting;
    lastError = null;
    prefs.setString('last_active_node', node.id);

    // Запоминаем запуск market-ноды → разблокирует жалобу на этот сервер.
    final gid = node.groupId;
    if (gid != null && gid.startsWith('market_')) {
      // ignore: discarded_futures
      LaunchedNodes.mark(prefs, node.reportUriHash);
    }

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
          killSwitch: settings.killSwitch,
          xrayTunMode: settings.xrayTunMode, // NEW
          keepDeviceAwake: settings.keepDeviceAwake, // NEW
          memoryLimitMB: settings.memoryLimitMB, // NEW
          proxyOnlyMode: settings.proxyOnlyMode, // NEW
          socksAuthUser: settings.socksAuthEnabled ? settings.socksAuthUsername : '', // NEW
          socksAuthPass: settings.socksAuthEnabled ? settings.socksAuthPassword : '', // NEW
        );
        if (!ok) {
          await Hysteria2Manager.stop();
          throw Exception('Не удалось запустить TUN VpnService');
        }
      } else {
        final config = xrayConfigForNode(
          node,
          packetSniffing: settings.packetAnalysis,
          useMux: settings.useMux,
          resolveDestination: settings.resolveDestination,
        );
        final ok = await bridge.startV2Ray(
          config: config,
          remark: node.name,
          perAppEnabled: perAppOn,
          allowedPackages: allowedPkgs,
          killSwitch: settings.killSwitch,
          xrayTunMode: settings.xrayTunMode, // NEW
          keepDeviceAwake: settings.keepDeviceAwake, // NEW
          memoryLimitMB: settings.memoryLimitMB, // NEW
          proxyOnlyMode: settings.proxyOnlyMode, // NEW
          socksAuthUser: settings.socksAuthEnabled ? settings.socksAuthUsername : '', // NEW
          socksAuthPass: settings.socksAuthEnabled ? settings.socksAuthPassword : '', // NEW
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
      // Сервер не поднялся — пробуем следующий (если включён failover и юзер
      // не отменял). Cap/backoff внутри FailoverController защищают от петли.
      await _tryFailover(failedId: node.id);
    }
  }

  /// Подключение в режиме обхода DPI (ciadpi напрямую, без VPN-сервера).
  /// Серверная нода не нужна; failover в этом режиме не применяется.
  @override
  Future<void> connectByeDpi() async {
    if (status == VpnStatus.connecting) return;
    if (status == VpnStatus.connected) {
      await disconnect();
      await Future.delayed(const Duration(milliseconds: 300));
    }
    _failover.userStopped = true; // в режиме ByeDPI нет серверного failover
    status = VpnStatus.connecting;
    lastError = null;
    notifyListeners();

    try {
      final perAppOn = perApp.enabled;
      final allowedPkgs = perAppOn ? perApp.includedPackages : const <String>[];
      final ok = await bridge.startByeDpi(
        args: buildByeDpiArgs(settings),
        remark: 'Обход DPI',
        perAppEnabled: perAppOn,
        allowedPackages: allowedPkgs,
        killSwitch: settings.killSwitch,
        keepDeviceAwake: settings.keepDeviceAwake, // NEW
        memoryLimitMB: settings.memoryLimitMB, // NEW
        socksAuthUser: settings.socksAuthEnabled ? settings.socksAuthUsername : '', // NEW
        socksAuthPass: settings.socksAuthEnabled ? settings.socksAuthPassword : '', // NEW
      );
      if (!ok) throw Exception('Не удалось запустить движок ByeDPI');
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
    // Пользователь сам отключился → failover не должен срабатывать на этом стопе.
    _failover.userStopped = true;
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

        // Накопительная аналитика для авторов market-подписок: если активная
        // нода принадлежит группе из маркета (id вида market_<id>) и юзер
        // залогинен — шлём дельты трафика и длительность с привязкой к устройству.
        final gid = node.groupId;
        if (currentUser != null && gid != null && gid.startsWith('market_')) {
          final marketId = int.tryParse(gid.substring('market_'.length));
          if (marketId != null &&
              (stats.rxBytes > 0 || stats.txBytes > 0 || durationSec > 0)) {
            // ignore: discarded_futures
            DeviceId.get().then((dh) => MarketApi.usageReport(
                  groupId: marketId,
                  deviceHash: dh,
                  uploadDelta: stats.txBytes,
                  downloadDelta: stats.rxBytes,
                  seconds: durationSec,
                ));
          }
        }

        // Платная подписка маркета (добавлена по /market/paid_sub/<code>):
        // дельты шлём с access_code — сервер списывает трафик-пакет покупки
        // и блокирует выдачу нод при исчерпании.
        if (gid != null && !gid.startsWith('market_')) {
          final grp = groups.where((g) => g.id == gid).cast<VpnGroup?>().firstOrNull;
          final m = RegExp(r'/market/paid_sub/([A-Za-z0-9]+)')
              .firstMatch(grp?.sourceUrl ?? '');
          if (m != null &&
              (stats.rxBytes > 0 || stats.txBytes > 0 || durationSec > 0)) {
            // ignore: discarded_futures
            DeviceId.get().then((dh) => MarketApi.paidUsageReport(
                  accessCode: m.group(1)!,
                  deviceHash: dh,
                  uploadDelta: stats.txBytes,
                  downloadDelta: stats.rxBytes,
                  seconds: durationSec,
                ));
          }
        }
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

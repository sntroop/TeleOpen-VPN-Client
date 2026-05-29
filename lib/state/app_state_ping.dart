// lib/state/app_state_ping.dart
//
// Пинг нод (все сразу / одна). part of app_state.

part of 'app_state.dart';

mixin AppStatePing on AppStateBase {
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
}

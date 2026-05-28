import 'dart:async';
import 'dart:io';

class TcpPing {
  
  static Future<int?> ping(String host, int port, {Duration timeout = const Duration(seconds: 4)}) async {
    final sw = Stopwatch()..start();
    try {
      final sock = await Socket.connect(host, port, timeout: timeout);
      sw.stop();
      sock.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  
  static Future<void> pingAll(
    List<({String host, int port})> targets,
    void Function(int index, int? ms) onResult, {
    int concurrency = 8,
  }) async {
    int next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= targets.length) return;
        final t = targets[i];
        final ms = await ping(t.host, t.port);
        onResult(i, ms);
      }
    }
    await Future.wait(List.generate(concurrency, (_) => worker()));
  }
}

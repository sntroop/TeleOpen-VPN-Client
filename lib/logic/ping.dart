// lib/logic/ping.dart
//
// Пинг нод. Поддерживает три режима (AppSettings.pingMode):
//   TCP  — открываем сокет к host:port, замеряем время до handshake;
//   UDP  — шлём датаграмму на host:port, ждём любой ответ (best-effort:
//          многие сервера на «голый» UDP не отвечают → null);
//   HTTP — реальная задержка через туннель, считается не здесь, а в
//          app_state_ping через нативный measureOutboundDelay (нужно ядро).

import 'dart:async';
import 'dart:io';

class TcpPing {
  /// Возвращает ms до соединения, или null если не удалось.
  static Future<int?> ping(String host, int port, {Duration timeout = const Duration(seconds: 4)}) async {
    final sw = Stopwatch()..start();
    try {
      final sock = await Socket.connect(host, port, timeout: timeout);
      sw.stop();
      sock.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      // Недоступность/таймаут — это и есть результат пинга (null). Логировать
      // не нужно: pingAll вызывает этот метод по каждой ноде, лог бы засорялся.
      return null;
    }
  }

  /// UDP-зонд: отправляем минимальную датаграмму и ждём любой ответ от host:port.
  /// Best-effort — на UDP-протоколах (hysteria2/tuic/quic) сервер может ответить,
  /// но на TCP-протоколах ответа не будет → вернётся null.
  static Future<int?> pingUdp(String host, int port,
      {Duration timeout = const Duration(seconds: 4)}) async {
    RawDatagramSocket? sock;
    final completer = Completer<int?>();
    final sw = Stopwatch()..start();
    Timer? timer;
    try {
      final addr = (await InternetAddress.lookup(host)
              .timeout(const Duration(seconds: 3)))
          .firstOrNull;
      if (addr == null) return null;

      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock.listen((event) {
        if (event == RawSocketEvent.read && !completer.isCompleted) {
          final dg = sock!.receive();
          if (dg != null) {
            sw.stop();
            completer.complete(sw.elapsedMilliseconds);
          }
        }
      });
      sock.send(const [0x00], addr, port);

      timer = Timer(timeout, () {
        if (!completer.isCompleted) completer.complete(null);
      });
      return await completer.future;
    } catch (_) {
      return null;
    } finally {
      timer?.cancel();
      sock?.close();
    }
  }

  /// Пинг сразу нескольких узлов с ограничением параллелизма.
  /// [udp] = true → используем UDP-зонд вместо TCP-handshake.
  static Future<void> pingAll(
    List<({String host, int port})> targets,
    void Function(int index, int? ms) onResult, {
    int concurrency = 8,
    bool udp = false,
  }) async {
    int next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= targets.length) return;
        final t = targets[i];
        final ms = udp ? await pingUdp(t.host, t.port) : await ping(t.host, t.port);
        onResult(i, ms);
      }
    }
    await Future.wait(List.generate(concurrency, (_) => worker()));
  }
}

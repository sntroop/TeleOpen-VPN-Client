// lib/logic/speed_benchmark.dart
//
// Самописный бенчмарк скорости на dart:io. НЕ используем сторонний плагин:
// flutter_internet_speed_test_pro оборачивал заброшенную нативку
// (fr.bmartel.speedtest, ~2019) + выбор сервера Fast.com — download/upload
// зависали на 0 и с VPN, и без. Плюс его фолбэк-сервер ходит по http://, а
// network_security_config теперь запрещает cleartext.
//
// Здесь меряем напрямую через Cloudflare (https, без cleartext-проблем):
//   download: GET https://speed.cloudflare.com/__down?bytes=N
//   upload:   POST https://speed.cloudflare.com/__up
//
// Два известных режима отказа прошлой самописной версии и как закрыты:
//   1. «стримы зависали — соединение есть, байты не идут»  → watchdog:
//      если N секунд нет новых байт, останавливаемся с тем, что намеряли.
//   2. «DNS speed.cloudflare.com рандомно падал с Failed host lookup» →
//      один переиспользуемый HttpClient (DNS кешируется) + ретрай коннекта.
//
// Тест ограничен по времени (не по объёму): крутится _testWindow секунд и
// считает среднюю скорость за окно. Публичный API не менялся — UI не трогаем.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'crash_log.dart';

/// Фаза теста.
enum SpeedTestPhase { idle, latency, download, upload, done }

/// Итоговый результат теста.
class SpeedTestResult {
  final double downloadMbps;
  final double uploadMbps;
  final int pingMs;
  final double jitterMs;
  final DateTime timestamp;

  const SpeedTestResult({
    required this.downloadMbps,
    required this.uploadMbps,
    required this.pingMs,
    required this.jitterMs,
    required this.timestamp,
  });
}

/// Колбэк прогресса — сигнатура та же, что и раньше, чтобы UI не ломать.
typedef SpeedTestProgress = void Function({
  required SpeedTestPhase phase,
  required double progress, // 0.0 .. 1.0
  required double currentSpeed, // Мбит/с
  required int pingMs,
  required double jitterMs,
});

/// Основной класс бенчмарка.
class SpeedBenchmark {
  bool _cancelled = false;
  HttpClient? _client;

  // Сколько секунд крутим каждую фазу и за сколько тишины считаем зависанием.
  static const _testWindow = Duration(seconds: 10);
  static const _idleTimeout = Duration(seconds: 5);
  static const _downUrl = 'https://speed.cloudflare.com/__down?bytes=104857600';
  static const _upUrl = 'https://speed.cloudflare.com/__up';

  /// Отменить текущий тест.
  void cancel() {
    _cancelled = true;
    try {
      _client?.close(force: true);
    } catch (e) {
      CrashLog.note('speedtest', 'client.close бросил: $e');
    }
  }

  /// Полный тест: ping → download → upload.
  /// Возвращает результат или null если тест упал/отменён.
  Future<SpeedTestResult?> run(SpeedTestProgress onProgress) async {
    _cancelled = false;

    final (pingMs, jitterMs) = await _measureLatency(onProgress);
    if (_cancelled) {
      onProgress(
        phase: SpeedTestPhase.done,
        progress: 1.0, currentSpeed: 0,
        pingMs: pingMs, jitterMs: jitterMs,
      );
      return null;
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 10)
      ..autoUncompress = false; // не даём gzip искажать измеряемый объём
    _client = client;

    double downloadMbps = 0;
    double uploadMbps = 0;
    try {
      CrashLog.note('speedtest', 'старт (самописный, cloudflare)');
      downloadMbps = await _measureDownload(client, onProgress, pingMs, jitterMs);
      if (!_cancelled) {
        uploadMbps = await _measureUpload(client, onProgress, pingMs, jitterMs);
      }
    } catch (e, st) {
      CrashLog.note('speedtest', 'тест упал: $e\n$st');
    } finally {
      try {
        client.close(force: true);
      } catch (_) {}
      _client = null;
    }

    if (_cancelled) return null;

    onProgress(
      phase: SpeedTestPhase.done,
      progress: 1.0, currentSpeed: 0,
      pingMs: pingMs, jitterMs: jitterMs,
    );
    CrashLog.note('speedtest',
        'готово: ↓${downloadMbps.toStringAsFixed(1)} ↑${uploadMbps.toStringAsFixed(1)} Мбит/с');

    return SpeedTestResult(
      downloadMbps: downloadMbps,
      uploadMbps: uploadMbps,
      pingMs: pingMs,
      jitterMs: jitterMs,
      timestamp: DateTime.now(),
    );
  }

  /// Открыть запрос с одним ретраем — лечит рандомный Failed host lookup.
  Future<HttpClientResponse> _openWithRetry(
      Future<HttpClientRequest> Function() open) async {
    try {
      final req = await open();
      return await req.close();
    } on SocketException catch (e) {
      CrashLog.note('speedtest', 'коннект упал ($e), ретрай через 400мс');
      await Future.delayed(const Duration(milliseconds: 400));
      final req = await open();
      return await req.close();
    }
  }

  // ── DOWNLOAD ───────────────────────────────────────────────────────────────
  Future<double> _measureDownload(
    HttpClient client,
    SpeedTestProgress onProgress,
    int pingMs,
    double jitterMs,
  ) async {
    onProgress(
      phase: SpeedTestPhase.download,
      progress: 0, currentSpeed: 0, pingMs: pingMs, jitterMs: jitterMs,
    );

    final resp =
        await _openWithRetry(() => client.getUrl(Uri.parse(_downUrl)));

    final completer = Completer<double>();
    final sw = Stopwatch()..start();
    var bytes = 0;
    StreamSubscription<List<int>>? sub;
    Timer? watchdog;

    double mbps() {
      final secs = sw.elapsedMilliseconds / 1000.0;
      return secs > 0 ? (bytes * 8 / 1e6) / secs : 0;
    }

    void finish() {
      watchdog?.cancel();
      sub?.cancel();
      if (!completer.isCompleted) completer.complete(mbps());
    }

    void armWatchdog() {
      watchdog?.cancel();
      watchdog = Timer(_idleTimeout, () {
        CrashLog.note('speedtest', 'download: $_idleTimeout без байт — стоп');
        finish();
      });
    }

    sub = resp.listen(
      (chunk) {
        if (_cancelled) {
          finish();
          return;
        }
        bytes += chunk.length;
        armWatchdog();
        final elapsed = sw.elapsedMilliseconds;
        onProgress(
          phase: SpeedTestPhase.download,
          progress: (elapsed / _testWindow.inMilliseconds).clamp(0.0, 1.0),
          currentSpeed: mbps(),
          pingMs: pingMs,
          jitterMs: jitterMs,
        );
        if (elapsed >= _testWindow.inMilliseconds) finish();
      },
      onError: (e) {
        CrashLog.note('speedtest', 'download onError: $e');
        finish();
      },
      onDone: finish,
      cancelOnError: true,
    );

    armWatchdog();
    return completer.future;
  }

  // ── UPLOAD ───────────────────────────────────────────────────────────────
  Future<double> _measureUpload(
    HttpClient client,
    SpeedTestProgress onProgress,
    int pingMs,
    double jitterMs,
  ) async {
    onProgress(
      phase: SpeedTestPhase.upload,
      progress: 0, currentSpeed: 0, pingMs: pingMs, jitterMs: jitterMs,
    );

    final chunk = Uint8List(64 * 1024); // 64 КБ нулей на отправку
    final sw = Stopwatch()..start();
    var sent = 0;
    var stop = false;

    double mbps() {
      final secs = sw.elapsedMilliseconds / 1000.0;
      return secs > 0 ? (sent * 8 / 1e6) / secs : 0;
    }

    // Генератор тела: бэкпрешер addStream сам притормаживает нас под скорость
    // сокета, поэтому sent ≈ реально ушедшие в сеть байты.
    Stream<List<int>> body() async* {
      while (!stop &&
          !_cancelled &&
          sw.elapsedMilliseconds < _testWindow.inMilliseconds) {
        yield chunk;
        sent += chunk.length;
        onProgress(
          phase: SpeedTestPhase.upload,
          progress:
              (sw.elapsedMilliseconds / _testWindow.inMilliseconds).clamp(0.0, 1.0),
          currentSpeed: mbps(),
          pingMs: pingMs,
          jitterMs: jitterMs,
        );
        await Future<void>.delayed(Duration.zero); // отдать управление циклу
      }
    }

    try {
      final req = await client.postUrl(Uri.parse(_upUrl));
      req.headers.contentType = ContentType('application', 'octet-stream');
      req.headers.chunkedTransferEncoding = true;

      // Watchdog на весь upload: окно + запас на финальный ответ.
      final guard = Timer(_testWindow + const Duration(seconds: 6), () {
        stop = true;
      });

      await req.addStream(body());
      final resp = await req.close();
      await resp.drain<void>();
      guard.cancel();
    } catch (e) {
      CrashLog.note('speedtest', 'upload упал: $e');
    }

    return mbps();
  }

  // ── LATENCY (как было — TCP-handshake к 1.1.1.1, не зависит от DNS) ────────
  Future<(int, double)> _measureLatency(SpeedTestProgress onProgress) async {
    onProgress(
      phase: SpeedTestPhase.latency,
      progress: 0, currentSpeed: 0, pingMs: 0, jitterMs: 0,
    );

    const probes = 5;
    final pings = <int>[];
    for (var i = 0; i < probes; i++) {
      if (_cancelled) break;
      final sw = Stopwatch()..start();
      try {
        final sock = await Socket.connect(
          '1.1.1.1', 443,
          timeout: const Duration(seconds: 3),
        );
        sw.stop();
        pings.add(sw.elapsedMilliseconds);
        sock.destroy();
      } catch (e) {
        sw.stop();
        CrashLog.note('speedtest', 'latency probe #$i failed: $e');
      }
      onProgress(
        phase: SpeedTestPhase.latency,
        progress: (i + 1) / probes,
        currentSpeed: 0,
        pingMs: pings.isEmpty ? 0 : _median(pings),
        jitterMs: pings.length < 2 ? 0 : _jitter(pings),
      );
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (pings.isEmpty) return (0, 0.0);
    return (_median(pings), _jitter(pings));
  }

  int _median(List<int> xs) {
    final s = [...xs]..sort();
    return s[s.length ~/ 2];
  }

  double _jitter(List<int> xs) {
    if (xs.length < 2) return 0;
    var sum = 0.0;
    for (var i = 1; i < xs.length; i++) {
      sum += (xs[i] - xs[i - 1]).abs();
    }
    return sum / (xs.length - 1);
  }
}

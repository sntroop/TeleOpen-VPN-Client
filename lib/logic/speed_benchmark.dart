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
  // Окно прогрева upload: первые миллисекунды сокет глотает в send-буфер
  // мгновенно, давая ложный спайк. Эти мс исключаем из «установившейся»
  // скорости. До warmup всё равно показываем raw-скорость, чтобы не висел 0.
  static const _warmup = Duration(milliseconds: 500);
  // Фиксированный объём upload: шлём ровно столько и закрываемся (с известным
  // Content-Length). Бесконечный chunked под VPN-TUN капризничал.
  static const _upBytes = 20 * 1024 * 1024; // 20 МБ
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
    CrashLog.note('speedtest', 'run() вход');

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
    CrashLog.note('speedtest', 'download: старт GET $_downUrl');

    final resp =
        await _openWithRetry(() => client.getUrl(Uri.parse(_downUrl)));

    final completer = Completer<double>();
    final sw = Stopwatch()..start();
    var bytes = 0;
    StreamSubscription<List<int>>? sub;
    Timer? watchdog;
    Timer? ticker;

    double mbps() {
      final secs = sw.elapsedMilliseconds / 1000.0;
      return secs > 0 ? (bytes * 8 / 1e6) / secs : 0;
    }

    void finish() {
      ticker?.cancel();
      watchdog?.cancel();
      sub?.cancel();
      if (!completer.isCompleted) {
        CrashLog.note('speedtest',
            'download: итог $bytes байт за ${sw.elapsedMilliseconds}мс, ${mbps().toStringAsFixed(1)} Мбит/с');
        completer.complete(mbps());
      }
    }

    void armWatchdog() {
      watchdog?.cancel();
      watchdog = Timer(_idleTimeout, () {
        CrashLog.note('speedtest',
            'download: $_idleTimeout без байт (получено $bytes) — стоп');
        finish();
      });
    }

    // Прогресс шлём по таймеру, НЕЗАВИСИМО от прихода чанков. Иначе при рваном
    // или нулевом трафике фаза download не отображалась бы вовсе (раньше
    // onProgress висел только в chunk-колбэке) и экран сразу прыгал на upload.
    ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      onProgress(
        phase: SpeedTestPhase.download,
        progress: (sw.elapsedMilliseconds / _testWindow.inMilliseconds)
            .clamp(0.0, 1.0),
        currentSpeed: mbps(),
        pingMs: pingMs,
        jitterMs: jitterMs,
      );
    });

    sub = resp.listen(
      (chunk) {
        if (_cancelled) {
          finish();
          return;
        }
        bytes += chunk.length;
        armWatchdog();
        if (sw.elapsedMilliseconds >= _testWindow.inMilliseconds) finish();
      },
      onError: (e) {
        CrashLog.note('speedtest', 'download onError ($bytes байт): $e');
        finish();
      },
      onDone: () {
        CrashLog.note('speedtest',
            'download onDone: $bytes байт за ${sw.elapsedMilliseconds}мс');
        finish();
      },
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
    CrashLog.note('speedtest', 'upload: старт POST $_upUrl, объём $_upBytes Б');

    final chunk = Uint8List(64 * 1024); // 64 КБ на отправку
    final sw = Stopwatch()..start();
    var sent = 0; // байты, РЕАЛЬНО принятые сокетом (после возврата из yield)
    var warmupSent = 0; // отсечка: сколько ушло за warmup-окно
    var warmupDone = false;
    var stop = false;
    var lastSent = 0; // для idle-watchdog: значение sent на прошлой проверке
    var idleMs = 0; // сколько мс подряд sent не растёт

    // Установившаяся скорость: первые _warmup мс сокет глотает в буфер
    // мгновенно — исключаем их, меряем (sent - warmupSent) за (elapsed - warmup).
    double mbps() {
      final secs = (sw.elapsedMilliseconds - _warmup.inMilliseconds) / 1000.0;
      if (secs <= 0) return 0;
      return ((sent - warmupSent) * 8 / 1e6) / secs;
    }

    // Сырая скорость по всему объёму — показываем ДО warmup, чтобы поле не
    // висело на 0 (раньше до warmup жёстко слался 0 → «вечный ноль»).
    double rawMbps() {
      final secs = sw.elapsedMilliseconds / 1000.0;
      return secs > 0 ? (sent * 8 / 1e6) / secs : 0;
    }

    // Прогресс гоним по таймеру, а НЕ из тела-генератора: при бэкпрешере
    // генератор блокируется на yield и события прогресса замерли бы (отсюда
    // была «заморозка»). Таймер тикает независимо + ловит idle (нет роста sent).
    final ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!warmupDone && sw.elapsedMilliseconds >= _warmup.inMilliseconds) {
        warmupDone = true;
        warmupSent = sent;
      }
      // idle-watchdog: если sent не растёт _idleTimeout подряд — сокет не
      // забирает байты (мёртвый канал под TUN) → обрываем, чтобы не висеть.
      if (sent == lastSent) {
        idleMs += 250;
        if (idleMs >= _idleTimeout.inMilliseconds && !stop) {
          stop = true;
          CrashLog.note('speedtest',
              'upload: $_idleTimeout без роста (sent=$sent) — стоп');
        }
      } else {
        idleMs = 0;
        lastSent = sent;
      }
      onProgress(
        phase: SpeedTestPhase.upload,
        progress:
            (sent / _upBytes).clamp(0.0, 1.0),
        currentSpeed: warmupDone ? mbps() : rawMbps(),
        pingMs: pingMs,
        jitterMs: jitterMs,
      );
    });

    // Тело: шлём ровно _upBytes (или пока не stop/cancel/окно). Счётчик растим
    // ПОСЛЕ yield — значит чанк реально забрал сокет (бэкпрешер addStream).
    Stream<List<int>> body() async* {
      while (!stop &&
          !_cancelled &&
          sent < _upBytes &&
          sw.elapsedMilliseconds < _testWindow.inMilliseconds) {
        yield chunk;
        sent += chunk.length;
      }
    }

    try {
      final req = await client.postUrl(Uri.parse(_upUrl));
      req.headers.contentType = ContentType('application', 'octet-stream');
      // Известный Content-Length вместо бесконечного chunked — детерминированный
      // приём, под VPN-TUN надёжнее. body() обязан отдать ровно _upBytes; если
      // оборвёмся раньше (watchdog/окно), close() кинет ошибку — её ловит catch.
      req.headers.contentLength = _upBytes;

      // Watchdog на весь upload: окно + запас на финальный ответ.
      final guard = Timer(_testWindow + const Duration(seconds: 6), () {
        stop = true;
      });

      await req.addStream(body());
      final resp = await req.close();
      await resp.drain<void>();
      guard.cancel();
    } catch (e) {
      CrashLog.note('speedtest', 'upload: соединение/отправка прервана (sent=$sent): $e');
    } finally {
      ticker.cancel();
    }

    final result = warmupDone ? mbps() : rawMbps();
    CrashLog.note('speedtest',
        'upload: итог sent=$sent за ${sw.elapsedMilliseconds}мс, ${result.toStringAsFixed(1)} Мбит/с');
    return result;
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

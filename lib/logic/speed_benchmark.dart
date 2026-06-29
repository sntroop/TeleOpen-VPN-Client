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
  // ВАЖНО: cloudflare __down отдаёт 403 (тело 1 байт!) на слишком большой
  // bytes — раньше тут было 104857600 (100МБ) → download мерил «1 байт, 0 Мбит/с».
  // 25МБ заведомо ниже лимита и хватает, чтобы намерить скорость за окно.
  static const _downBytes = 25 * 1024 * 1024; // 26214400
  static const _downUrl =
      'https://speed.cloudflare.com/__down?bytes=$_downBytes';
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

    // После долгого простоя DNS-кеш/idle-сокеты протухают — прогреваем резолв
    // speed.cloudflare.com заранее, чтобы первая фаза не падала на host lookup.
    await _warmDns();

    double downloadMbps = 0;
    double uploadMbps = 0;
    try {
      CrashLog.note('speedtest', 'старт (самописный, cloudflare)');
      // Каждую фазу при нулевом результате повторяем один раз со СВЕЖИМ
      // HttpClient: после фона в пуле могло остаться мёртвое соединение,
      // которое отдавало 0 (или только одну из фаз). Свежий клиент это лечит.
      downloadMbps = await _runPhase(
        (cl) => _measureDownload(cl, onProgress, pingMs, jitterMs),
        'download',
      );
      if (!_cancelled) {
        uploadMbps = await _runPhase(
          (cl) => _measureUpload(cl, onProgress, pingMs, jitterMs),
          'upload',
        );
      }
    } catch (e, st) {
      CrashLog.note('speedtest', 'тест упал: $e\n$st');
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

  /// Прогрев DNS: после долгого фона резолв speed.cloudflare.com часто падает
  /// первым же запросом (Failed host lookup) — резолвим заранее с ретраем,
  /// чтобы фазы не возвращали 0 из-за протухшего DNS-кеша.
  Future<void> _warmDns() async {
    for (var i = 0; i < 2; i++) {
      if (_cancelled) return;
      try {
        final r = await InternetAddress.lookup('speed.cloudflare.com')
            .timeout(const Duration(seconds: 4));
        if (r.isNotEmpty) return;
      } catch (e) {
        CrashLog.note('speedtest', 'warmDns попытка ${i + 1}: $e');
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  /// Прогоняет фазу со свежим HttpClient и, если результат нулевой (мёртвое
  /// соединение/обрыв после фона), повторяет один раз. Так лечится «иногда
  /// только download / только upload / совсем ничего» после долгого простоя.
  Future<double> _runPhase(
      Future<double> Function(HttpClient) phase, String name) async {
    Future<double> attempt() async {
      try {
        return await _withFreshClient(phase);
      } catch (e) {
        // Фаза целиком упала (оба ретрая коннекта) — считаем нулём, чтобы
        // ниже сработал повтор и НЕ оборвалась следующая фаза (upload).
        CrashLog.note('speedtest', '$name упал: $e');
        return 0;
      }
    }

    var result = await attempt();
    if (!_cancelled && result <= 0) {
      CrashLog.note('speedtest', '$name=0 — повтор фазы со свежим клиентом');
      await Future.delayed(const Duration(milliseconds: 300));
      if (!_cancelled) result = await attempt();
    }
    return result;
  }

  /// Создаёт свежий HttpClient (свой пул соединений), выполняет фазу и
  /// гарантированно его закрывает. _client держим для cancel().
  Future<double> _withFreshClient(
      Future<double> Function(HttpClient) phase) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 10)
      ..autoUncompress = false; // не даём gzip искажать измеряемый объём
    _client = client;
    try {
      return await phase(client);
    } finally {
      try {
        client.close(force: true);
      } catch (_) {}
      if (identical(_client, client)) _client = null;
    }
  }

  /// Открыть запрос с одним ретраем — лечит рандомный Failed host lookup и
  /// прочие сетевые сбои на установке соединения (не только SocketException).
  Future<HttpClientResponse> _openWithRetry(
      Future<HttpClientRequest> Function() open) async {
    try {
      final req = await open();
      return await req.close();
    } on Exception catch (e) {
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

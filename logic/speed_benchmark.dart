import 'dart:async';
import 'dart:io';

import 'package:flutter_internet_speed_test_pro/flutter_internet_speed_test_pro.dart'
    as fistp;

import 'crash_log.dart';

enum SpeedTestPhase { idle, latency, download, upload, done }

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

typedef SpeedTestProgress = void Function({
  required SpeedTestPhase phase,
  required double progress,     
  required double currentSpeed, 
  required int pingMs,
  required double jitterMs,
});

class SpeedBenchmark {
  bool _cancelled = false;
  late fistp.FlutterInternetSpeedTest _engine;

  
  void cancel() {
    _cancelled = true;
    try {
      _engine.cancelTest();
    } catch (e) {
      CrashLog.note('speedtest', 'cancelTest бросил: $e');
    }
  }

  
  
  Future<SpeedTestResult?> run(SpeedTestProgress onProgress) async {
    _cancelled = false;
    _engine = fistp.FlutterInternetSpeedTest();

    final completer = Completer<SpeedTestResult?>();

    
    
    
    final pingAndJitter = await _measureLatency(onProgress);
    final pingMs = pingAndJitter.$1;
    final jitterMs = pingAndJitter.$2;

    if (_cancelled) {
      onProgress(
        phase: SpeedTestPhase.done,
        progress: 1.0, currentSpeed: 0,
        pingMs: pingMs, jitterMs: jitterMs,
      );
      return null;
    }

    
    double downloadMbps = 0;
    double uploadMbps = 0;
    bool downloadDone = false;
    SpeedTestPhase currentPhase = SpeedTestPhase.download;

    CrashLog.note('speedtest', 'старт через flutter_internet_speed_test_pro');

    try {
      await _engine.startTesting(
        
        
        useFastApi: true,

        onStarted: () {
          currentPhase = SpeedTestPhase.download;
          onProgress(
            phase: currentPhase, progress: 0, currentSpeed: 0,
            pingMs: pingMs, jitterMs: jitterMs,
          );
        },

        
        
        onProgress: (double percent, fistp.TestResult data) {
          if (_cancelled) return;
          currentPhase = downloadDone
              ? SpeedTestPhase.upload
              : SpeedTestPhase.download;
          
          onProgress(
            phase: currentPhase,
            progress: (percent / 100.0).clamp(0.0, 1.0),
            currentSpeed: _toMbps(data),
            pingMs: pingMs,
            jitterMs: jitterMs,
          );
        },

        onDownloadComplete: (fistp.TestResult data) {
          downloadMbps = _toMbps(data);
          downloadDone = true;
          CrashLog.note('speedtest',
              'download готов: ${downloadMbps.toStringAsFixed(2)} Мбит/с');
        },

        onUploadComplete: (fistp.TestResult data) {
          uploadMbps = _toMbps(data);
          CrashLog.note('speedtest',
              'upload готов: ${uploadMbps.toStringAsFixed(2)} Мбит/с');
        },

        onCompleted: (fistp.TestResult dl, fistp.TestResult ul) {
          
          
          if (downloadMbps == 0) downloadMbps = _toMbps(dl);
          if (uploadMbps == 0) uploadMbps = _toMbps(ul);

          onProgress(
            phase: SpeedTestPhase.done,
            progress: 1.0,
            currentSpeed: 0,
            pingMs: pingMs,
            jitterMs: jitterMs,
          );
          if (!completer.isCompleted) {
            completer.complete(SpeedTestResult(
              downloadMbps: downloadMbps,
              uploadMbps: uploadMbps,
              pingMs: pingMs,
              jitterMs: jitterMs,
              timestamp: DateTime.now(),
            ));
          }
        },

        onError: (String errorMessage, String speedTestError) {
          CrashLog.note('speedtest',
              'ошибка плагина: $errorMessage ($speedTestError)');
          if (!completer.isCompleted) completer.complete(null);
        },

        onCancel: () {
          CrashLog.note('speedtest', 'тест отменён пользователем');
          if (!completer.isCompleted) completer.complete(null);
        },
      );
    } catch (e, st) {
      CrashLog.note('speedtest', 'startTesting бросил: $e\n$st');
      if (!completer.isCompleted) completer.complete(null);
    }

    return completer.future;
  }

  
  
  double _toMbps(fistp.TestResult data) {
    final speed = data.transferRate;
    
    
    try {
      final unit = data.unit;
      if (unit == fistp.SpeedUnit.kbps) return speed / 1000.0;
    } catch (_) {}
    return speed;
  }

  
  
  
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

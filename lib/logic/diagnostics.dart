// lib/logic/diagnostics.dart
//
// Диагностика VPN-сервера: серия тестов выполняется последовательно,
// результаты стримятся в UI через колбэки.
//
// Внимание: тесты идут НАПРЯМУЮ к серверу (без VPN-туннеля), поэтому
// проверяют именно доступность endpoint'а, а не скорость через прокси.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/vpn_node.dart';

// ─── Модель результата одного теста ─────────────────────────────────────────

enum DiagStatus { pending, running, ok, warn, fail, skipped }

class DiagStepResult {
  final String id;
  final String title;
  DiagStatus status;
  String? primary;   // основное значение ("23 ms", "OK", "1.2 MB/s")
  String? detail;    // подробности ("min/avg/max/jitter: 18/23/31/4 ms")
  Duration? elapsed;

  DiagStepResult({
    required this.id,
    required this.title,
    this.status = DiagStatus.pending,
    this.primary,
    this.detail,
    this.elapsed,
  });
}

// ─── Итоговый отчёт ──────────────────────────────────────────────────────────

class DiagnosticsReport {
  final VpnNode node;
  final List<DiagStepResult> steps;
  final DateTime startedAt;
  final DateTime finishedAt;

  DiagnosticsReport({
    required this.node,
    required this.steps,
    required this.startedAt,
    required this.finishedAt,
  });

  /// 0..100 — общая «оценка качества» (упрощённая)
  int get score {
    int okCount = steps.where((s) => s.status == DiagStatus.ok).length;
    int total = steps.where((s) => s.status != DiagStatus.skipped).length;
    if (total == 0) return 0;
    return ((okCount / total) * 100).round();
  }

  String get verdict {
    final s = score;
    if (s >= 85) return 'Отличный сервер';
    if (s >= 65) return 'Рабочий, есть нюансы';
    if (s >= 40) return 'Нестабильный';
    return 'Сервер недоступен';
  }
}

// ─── Раннер тестов ───────────────────────────────────────────────────────────

class DiagnosticsRunner {
  final VpnNode node;
  final void Function(String stepId, DiagStepResult result) onUpdate;

  late final List<DiagStepResult> _steps = [
    DiagStepResult(id: 'dns',     title: 'Резолв DNS'),
    DiagStepResult(id: 'tcp',     title: 'TCP-пинг'),
    DiagStepResult(id: 'port',    title: 'Доступность порта'),
    DiagStepResult(id: 'tls',     title: 'TLS handshake'),
    DiagStepResult(id: 'http',    title: 'HTTP проба'),
    DiagStepResult(id: 'geo',     title: 'Геолокация IP'),
    DiagStepResult(id: 'rdns',    title: 'Reverse DNS'),
    DiagStepResult(id: 'bench',   title: 'Бенчмарк отклика'),
  ];

  List<DiagStepResult> get steps => _steps;

  DiagnosticsRunner({required this.node, required this.onUpdate});

  void _update(String id, void Function(DiagStepResult) mut) {
    final s = _steps.firstWhere((e) => e.id == id);
    mut(s);
    onUpdate(id, s);
  }

  Future<DiagnosticsReport> run() async {
    final start = DateTime.now();
    String? resolvedIp;

    // 1. DNS resolve
    _update('dns', (s) => s.status = DiagStatus.running);
    final dnsSw = Stopwatch()..start();
    try {
      final isLiteralIp = _isIpLiteral(node.address);
      if (isLiteralIp) {
        dnsSw.stop();
        resolvedIp = node.address;
        _update('dns', (s) {
          s.status = DiagStatus.ok;
          s.primary = 'IP-адрес';
          s.detail = '${node.address} (литеральный IP, резолв не требуется)';
          s.elapsed = dnsSw.elapsed;
        });
      } else {
        final addrs = await InternetAddress.lookup(node.address)
            .timeout(const Duration(seconds: 5));
        dnsSw.stop();
        if (addrs.isEmpty) throw Exception('Не удалось разрешить домен');
        resolvedIp = addrs.first.address;
        _update('dns', (s) {
          s.status = DiagStatus.ok;
          s.primary = '${dnsSw.elapsedMilliseconds} мс';
          s.detail = '$resolvedIp · ${addrs.length} запис(и/ей)';
          s.elapsed = dnsSw.elapsed;
        });
      }
    } catch (e) {
      dnsSw.stop();
      _update('dns', (s) {
        s.status = DiagStatus.fail;
        s.primary = 'Ошибка';
        s.detail = _shortError(e);
        s.elapsed = dnsSw.elapsed;
      });
    }

    // 2. TCP-пинг (5 попыток)
    _update('tcp', (s) => s.status = DiagStatus.running);
    final pings = <int>[];
    int failed = 0;
    for (var i = 0; i < 5; i++) {
      final ms = await _tcpPing(node.address, node.port,
          timeout: const Duration(seconds: 3));
      if (ms != null) {
        pings.add(ms);
      } else {
        failed++;
      }
      // микропауза чтоб не нагружать сервер
      await Future.delayed(const Duration(milliseconds: 80));
    }
    if (pings.isEmpty) {
      _update('tcp', (s) {
        s.status = DiagStatus.fail;
        s.primary = 'Нет ответа';
        s.detail = '0 из 5 успешных попыток';
      });
    } else {
      pings.sort();
      final minP = pings.first;
      final maxP = pings.last;
      final avg = pings.reduce((a, b) => a + b) / pings.length;
      final jitter = pings.length > 1 ? (maxP - minP) : 0;
      _update('tcp', (s) {
        s.status = failed > 0 ? DiagStatus.warn : DiagStatus.ok;
        s.primary = '${avg.toStringAsFixed(0)} мс';
        s.detail =
            'min/avg/max: $minP/${avg.toStringAsFixed(0)}/$maxP · jitter $jitter мс · потери $failed/5';
      });
    }

    // 3. Доступность порта (по результатам TCP-пинга)
    _update('port', (s) {
      if (pings.isNotEmpty) {
        s.status = DiagStatus.ok;
        s.primary = '${node.port}/tcp открыт';
        s.detail = 'Подключение к ${node.address}:${node.port} установлено';
      } else {
        s.status = DiagStatus.fail;
        s.primary = 'Порт закрыт';
        s.detail = 'Не удалось подключиться к ${node.address}:${node.port}';
      }
    });

    // 4. TLS handshake (если есть SNI или порт типичный TLS)
    final sni = (node.params['sni'] ?? node.params['host'] ?? '').toString();
    final usesTls = sni.isNotEmpty ||
        (node.params['security']?.toString().toLowerCase().contains('tls') ?? false) ||
        node.params['security']?.toString().toLowerCase() == 'reality' ||
        node.port == 443;

    if (!usesTls) {
      _update('tls', (s) {
        s.status = DiagStatus.skipped;
        s.primary = 'Не используется';
        s.detail = 'Сервер работает без TLS';
      });
    } else {
      _update('tls', (s) => s.status = DiagStatus.running);
      final tlsSw = Stopwatch()..start();
      // MED-3: НЕ принимаем любой сертификат молча. Для диагностики коннект
      // всё же завершаем (VPN-серверы часто маскируют/самоподписывают cert),
      // но факт невалидности фиксируем и показываем как warn, а не тихий OK.
      var badCert = false;
      try {
        final host = sni.isNotEmpty ? sni : node.address;
        final sock = await SecureSocket.connect(
          node.address,
          node.port,
          onBadCertificate: (_) {
            badCert = true;
            return true; // продолжаем только ради замера; результат пометим warn
          },
          timeout: const Duration(seconds: 6),
          context: SecurityContext(withTrustedRoots: true),
          supportedProtocols: ['h2', 'http/1.1'],
        );
        tlsSw.stop();
        final cipher = sock.selectedProtocol ?? "?";
        final peerCert = sock.peerCertificate;
        final subject = peerCert?.subject ?? '?';
        sock.destroy();
        _update('tls', (s) {
          s.status = badCert ? DiagStatus.warn : DiagStatus.ok;
          s.primary = badCert
              ? 'Cert не доверен'
              : '${tlsSw.elapsedMilliseconds} мс';
          s.detail = badCert
              ? 'Сертификат не прошёл проверку (самоподписан/чужой CN). '
                  'SNI: $host · CN: ${_shortSubject(subject)}'
              : 'SNI: $host · ALPN: $cipher · CN: ${_shortSubject(subject)}';
          s.elapsed = tlsSw.elapsed;
        });
      } catch (e) {
        tlsSw.stop();
        // Для REALITY это нормально что TLS не установится напрямую
        final isReality =
            node.params['security']?.toString().toLowerCase() == 'reality';
        _update('tls', (s) {
          s.status = isReality ? DiagStatus.warn : DiagStatus.fail;
          s.primary = isReality ? 'REALITY' : 'Ошибка';
          s.detail = isReality
              ? 'REALITY не отвечает на обычный TLS — это нормально'
              : _shortError(e);
          s.elapsed = tlsSw.elapsed;
        });
      }
    }

    // 5. HTTP проба (только для портов 80/443/8080/8443)
    final httpPort = {80, 443, 8080, 8443, 2052, 2053, 2082, 2083, 2086, 2087, 2095, 2096}
        .contains(node.port);
    if (!httpPort) {
      _update('http', (s) {
        s.status = DiagStatus.skipped;
        s.primary = 'Пропущено';
        s.detail = 'Порт ${node.port} не типичен для HTTP';
      });
    } else {
      _update('http', (s) => s.status = DiagStatus.running);
      final httpSw = Stopwatch()..start();
      try {
        final scheme = (node.port == 443 || node.port == 8443) ? 'https' : 'http';
        final url = Uri.parse('$scheme://${node.address}:${node.port}/');
        final r = await http
            .get(url, headers: {'User-Agent': 'Mozilla/5.0 TeleOpen-Diag'})
            .timeout(const Duration(seconds: 8));
        httpSw.stop();
        final bytes = r.bodyBytes.length;
        _update('http', (s) {
          s.status = r.statusCode < 500 ? DiagStatus.ok : DiagStatus.warn;
          s.primary = 'HTTP ${r.statusCode}';
          s.detail = '${httpSw.elapsedMilliseconds} мс · '
              '${_formatBytes(bytes)} · '
              '${r.headers['server'] ?? "сервер не указан"}';
          s.elapsed = httpSw.elapsed;
        });
      } catch (e) {
        httpSw.stop();
        _update('http', (s) {
          s.status = DiagStatus.warn;
          s.primary = 'Нет ответа HTTP';
          s.detail = _shortError(e);
          s.elapsed = httpSw.elapsed;
        });
      }
    }

    // 6. Геолокация IP (через ip-api.com)
    _update('geo', (s) => s.status = DiagStatus.running);
    final geoSw = Stopwatch()..start();
    try {
      final ip = resolvedIp ?? node.address;
      final r = await http
          .get(Uri.parse(
              'http://ip-api.com/json/$ip?fields=status,country,regionName,city,isp,org,query'))
          .timeout(const Duration(seconds: 6));
      geoSw.stop();
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        if (j['status'] == 'success') {
          final country = j['country'] ?? '?';
          final city = j['city'] ?? '';
          final isp = j['isp'] ?? j['org'] ?? '?';
          _update('geo', (s) {
            s.status = DiagStatus.ok;
            s.primary = '$country${city.isNotEmpty ? " · $city" : ""}';
            s.detail = 'ISP: $isp · IP: ${j['query'] ?? ip}';
            s.elapsed = geoSw.elapsed;
          });
        } else {
          throw Exception('ip-api: ${j['message'] ?? "fail"}');
        }
      } else {
        throw Exception('HTTP ${r.statusCode}');
      }
    } catch (e) {
      geoSw.stop();
      _update('geo', (s) {
        s.status = DiagStatus.warn;
        s.primary = 'Недоступно';
        s.detail = _shortError(e);
        s.elapsed = geoSw.elapsed;
      });
    }

    // 7. Reverse DNS
    _update('rdns', (s) => s.status = DiagStatus.running);
    try {
      final ip = resolvedIp ?? node.address;
      final addr = InternetAddress(ip);
      final reverse = await addr.reverse().timeout(const Duration(seconds: 4));
      _update('rdns', (s) {
        if (reverse.host == ip || reverse.host.isEmpty) {
          s.status = DiagStatus.warn;
          s.primary = 'Нет PTR-записи';
          s.detail = 'IP не имеет обратного DNS';
        } else {
          s.status = DiagStatus.ok;
          s.primary = reverse.host;
          s.detail = 'PTR: $ip → ${reverse.host}';
        }
      });
    } catch (e) {
      _update('rdns', (s) {
        s.status = DiagStatus.warn;
        s.primary = 'Недоступно';
        s.detail = _shortError(e);
      });
    }

    // 8. Бенчмарк отклика (10 быстрых соединений подряд)
    _update('bench', (s) => s.status = DiagStatus.running);
    final benchSw = Stopwatch()..start();
    final benchTimes = <int>[];
    int benchFail = 0;
    for (var i = 0; i < 10; i++) {
      final ms = await _tcpPing(node.address, node.port,
          timeout: const Duration(seconds: 2));
      if (ms != null) {
        benchTimes.add(ms);
      } else {
        benchFail++;
      }
    }
    benchSw.stop();
    if (benchTimes.isEmpty) {
      _update('bench', (s) {
        s.status = DiagStatus.fail;
        s.primary = 'Нестабильно';
        s.detail = '0/10 успешных соединений за ${benchSw.elapsed.inSeconds}с';
      });
    } else {
      final avg = benchTimes.reduce((a, b) => a + b) / benchTimes.length;
      final stddev = _stddev(benchTimes);
      final successRate = (benchTimes.length / 10 * 100).round();
      _update('bench', (s) {
        s.status = benchFail > 2
            ? DiagStatus.warn
            : (avg < 100 ? DiagStatus.ok : DiagStatus.warn);
        s.primary = '${avg.toStringAsFixed(0)} мс · $successRate%';
        s.detail =
            'успешно ${benchTimes.length}/10 · σ ${stddev.toStringAsFixed(1)} мс · ${benchSw.elapsed.inMilliseconds} мс всего';
        s.elapsed = benchSw.elapsed;
      });
    }

    return DiagnosticsReport(
      node: node,
      steps: _steps,
      startedAt: start,
      finishedAt: DateTime.now(),
    );
  }

  // ─── Утилиты ──────────────────────────────────────────────────────────────

  Future<int?> _tcpPing(String host, int port, {required Duration timeout}) async {
    final sw = Stopwatch()..start();
    try {
      final sock = await Socket.connect(host, port, timeout: timeout);
      sw.stop();
      sock.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      // Недоступность/таймаут — штатный результат TCP-замера (null), не ошибка
      // приложения; логировать не нужно.
      return null;
    }
  }

  bool _isIpLiteral(String s) {
    // IPv4
    final ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
    if (ipv4.hasMatch(s)) return true;
    // IPv6 — упрощённая проверка
    if (s.contains(':') && !s.contains(' ')) return true;
    return false;
  }

  double _stddev(List<int> values) {
    if (values.length < 2) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) / values.length;
    return sqrt(variance);
  }

  String _shortError(Object e) {
    final s = e.toString();
    if (s.length > 80) return '${s.substring(0, 77)}...';
    return s;
  }

  String _shortSubject(String s) {
    // /CN=example.com → example.com
    final m = RegExp(r'CN=([^,/]+)').firstMatch(s);
    return m?.group(1) ?? s;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

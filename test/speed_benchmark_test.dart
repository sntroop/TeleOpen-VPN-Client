// Тесты бенчмарка скорости.
// Сеть здесь не дёргаем (на CI нет ни VPN, ни Android) — download/upload
// требуют реального сокета и проверяются на устройстве. Здесь фиксируем
// стабильность публичного API, который потребляет UI (speed_test_screen).

import 'package:flutter_test/flutter_test.dart';
import 'package:my_vpn/logic/speed_benchmark.dart';

void main() {
  group('SpeedTestResult', () {
    test('хранит переданные поля без искажений', () {
      final ts = DateTime(2026, 5, 30, 12, 0, 0);
      final r = SpeedTestResult(
        downloadMbps: 95.5,
        uploadMbps: 12.3,
        pingMs: 18,
        jitterMs: 2.5,
        timestamp: ts,
      );
      expect(r.downloadMbps, 95.5);
      expect(r.uploadMbps, 12.3);
      expect(r.pingMs, 18);
      expect(r.jitterMs, 2.5);
      expect(r.timestamp, ts);
    });
  });

  group('SpeedTestPhase', () {
    test('фазы идут в ожидаемом порядке (UI завязан на этот порядок)', () {
      expect(SpeedTestPhase.values, const [
        SpeedTestPhase.idle,
        SpeedTestPhase.latency,
        SpeedTestPhase.download,
        SpeedTestPhase.upload,
        SpeedTestPhase.done,
      ]);
    });
  });

  group('SpeedBenchmark.cancel', () {
    test('cancel до запуска не бросает', () {
      final b = SpeedBenchmark();
      expect(b.cancel, returnsNormally);
    });
  });
}

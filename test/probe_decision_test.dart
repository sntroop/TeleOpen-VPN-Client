// test/probe_decision_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:my_vpn/logic/connectivity_probe.dart';

void main() {
  group('ProbeDecider (порог 2)', () {
    test('один промах → не действуем', () {
      final d = ProbeDecider(failureThreshold: 2);
      expect(d.recordResult(false), isFalse);
      expect(d.consecutiveFailures, 1);
    });

    test('два промаха подряд → действуем один раз', () {
      final d = ProbeDecider(failureThreshold: 2);
      expect(d.recordResult(false), isFalse);
      expect(d.recordResult(false), isTrue); // порог достигнут
      // дальнейшие промахи не дёргают действие повторно
      expect(d.recordResult(false), isFalse);
    });

    test('успех между промахами сбрасывает счётчик', () {
      final d = ProbeDecider(failureThreshold: 2);
      d.recordResult(false);
      expect(d.recordResult(true), isFalse);
      expect(d.consecutiveFailures, 0);
      // снова нужно 2 промаха
      expect(d.recordResult(false), isFalse);
      expect(d.recordResult(false), isTrue);
    });

    test('успех после действия разрешает действовать снова', () {
      final d = ProbeDecider(failureThreshold: 2);
      d.recordResult(false);
      expect(d.recordResult(false), isTrue);
      d.recordResult(true); // связь восстановилась
      d.recordResult(false);
      expect(d.recordResult(false), isTrue); // новый эпизод
    });

    test('reset обнуляет состояние', () {
      final d = ProbeDecider(failureThreshold: 2);
      d.recordResult(false);
      d.reset();
      expect(d.consecutiveFailures, 0);
      expect(d.recordResult(false), isFalse);
    });
  });
}

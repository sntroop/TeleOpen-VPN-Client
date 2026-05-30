// test/kill_switch_logic_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:my_vpn/state/vpn_status.dart';

void main() {
  group('parseNativeStatus', () {
    test('CONNECTING / CONNECTED / STOPPED', () {
      expect(parseNativeStatus('CONNECTING').status, VpnStatus.connecting);
      expect(parseNativeStatus('CONNECTED').status, VpnStatus.connected);
      expect(parseNativeStatus('STOPPED').status, VpnStatus.stopped);
    });

    test('регистронезависимость', () {
      expect(parseNativeStatus('connected').status, VpnStatus.connected);
      expect(parseNativeStatus('Dropped').status, VpnStatus.error);
    });

    test('DROPPED → error + unexpectedDrop', () {
      final ev = parseNativeStatus('DROPPED');
      expect(ev.status, VpnStatus.error);
      expect(ev.unexpectedDrop, isTrue);
    });

    test('штатные статусы не помечены как обрыв', () {
      expect(parseNativeStatus('CONNECTED').unexpectedDrop, isFalse);
      expect(parseNativeStatus('STOPPED').unexpectedDrop, isFalse);
    });

    test('неизвестная строка → stopped, без обрыва', () {
      final ev = parseNativeStatus('whatever');
      expect(ev.status, VpnStatus.stopped);
      expect(ev.unexpectedDrop, isFalse);
    });
  });
}

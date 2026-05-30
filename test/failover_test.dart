// test/failover_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:my_vpn/logic/failover.dart';
import 'package:my_vpn/models/vpn_node.dart';

VpnNode _node(String id, {int? ping}) => VpnNode(
      id: id,
      name: id,
      address: '$id.example.com',
      port: 443,
      protocol: VpnProtocol.vless,
      rawUri: 'vless://$id',
      pingMs: ping,
    );

void main() {
  group('orderCandidates', () {
    test('по возрастанию пинга, упавшая нода исключена', () {
      final all = [
        _node('a', ping: 100),
        _node('b', ping: 30),
        _node('c', ping: 60),
      ];
      final ordered = FailoverController.orderCandidates(all,
          failedId: 'a', triedIds: {});
      expect(ordered.map((n) => n.id), ['b', 'c']);
    });

    test('null-пинг уходит в конец', () {
      final all = [_node('a', ping: null), _node('b', ping: 50)];
      final ordered = FailoverController.orderCandidates(all,
          failedId: 'x', triedIds: {});
      expect(ordered.map((n) => n.id), ['b', 'a']);
    });

    test('опробованные исключаются', () {
      final all = [_node('a', ping: 10), _node('b', ping: 20)];
      final ordered = FailoverController.orderCandidates(all,
          failedId: null, triedIds: {'a'});
      expect(ordered.map((n) => n.id), ['b']);
    });
  });

  group('FailoverController loop-cap', () {
    test('после maxAttempts — exhausted, кандидата нет', () {
      final fc = FailoverController(maxAttempts: 2);
      final all = [_node('a'), _node('b'), _node('c')];
      expect(fc.nextCandidate(all, 'x'), isNotNull);
      fc.registerAttempt('a');
      expect(fc.nextCandidate(all, 'x'), isNotNull);
      fc.registerAttempt('b');
      expect(fc.exhausted, isTrue);
      expect(fc.nextCandidate(all, 'x'), isNull);
    });

    test('backoff растёт и фиксируется на последнем', () {
      final fc = FailoverController(
        maxAttempts: 5,
        backoffs: const [Duration(seconds: 2), Duration(seconds: 5)],
      );
      expect(fc.backoffFor(0), const Duration(seconds: 2));
      expect(fc.backoffFor(1), const Duration(seconds: 5));
      expect(fc.backoffFor(2), const Duration(seconds: 5)); // зажат на последнем
    });
  });

  group('userStopped gate', () {
    test('при userStopped кандидат не выдаётся', () {
      final fc = FailoverController();
      fc.userStopped = true;
      expect(fc.canAttempt, isFalse);
      expect(fc.nextCandidate([_node('a')], 'x'), isNull);
    });

    test('reset снимает userStopped и обнуляет попытки', () {
      final fc = FailoverController(maxAttempts: 1);
      fc.registerAttempt('a');
      fc.userStopped = true;
      expect(fc.canAttempt, isFalse);
      fc.reset();
      expect(fc.canAttempt, isTrue);
      expect(fc.attempts, 0);
    });

    test('опробованная нода не предлагается повторно после reset-эпизода', () {
      final fc = FailoverController();
      final all = [_node('a', ping: 10), _node('b', ping: 20)];
      final first = fc.nextCandidate(all, 'x');
      fc.registerAttempt(first!.id);
      final second = fc.nextCandidate(all, 'x');
      expect(second!.id, isNot(first.id));
    });
  });
}

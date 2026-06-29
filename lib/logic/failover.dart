// lib/logic/failover.dart
//
// Чистая логика авто-failover (без сетевых вызовов и таймеров — тестируемая).
// Когда активный сервер не отвечает (ошибка коннекта ИЛИ подтверждённый обрыв),
// контроллер выбирает следующего кандидата по возрастанию пинга, ограничивает
// число попыток и задаёт backoff. Реальные connect()/задержки — в AppStateFailover.

import '../models/vpn_node.dart';

class FailoverController {
  /// Максимум попыток на один эпизод (защита от бесконечной петли).
  final int maxAttempts;

  /// Задержки между попытками; последняя используется для всех последующих.
  final List<Duration> backoffs;

  int _attempts = 0;
  final Set<String> _triedIds = {};

  /// Ставится, когда пользователь сам нажал «отключить» — failover не должен срабатывать.
  bool userStopped = false;

  FailoverController({
    this.maxAttempts = 3,
    this.backoffs = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
    ],
  });

  int get attempts => _attempts;
  bool get exhausted => _attempts >= maxAttempts;

  /// Можно ли сейчас пытаться переключиться.
  bool get canAttempt => !userStopped && !exhausted;

  /// Упорядочить кандидатов: по возрастанию пинга (null-пинг — в конец),
  /// исключив упавшую ноду и уже опробованные в этом эпизоде.
  static List<VpnNode> orderCandidates(
    List<VpnNode> all, {
    required String? failedId,
    required Set<String> triedIds,
  }) {
    final pool = all
        .where((n) => n.id != failedId && !triedIds.contains(n.id))
        .toList();
    pool.sort((a, b) {
      final pa = a.pingMs ?? 1 << 30; // null → максимально «далеко»
      final pb = b.pingMs ?? 1 << 30;
      return pa.compareTo(pb);
    });
    return pool;
  }

  /// Следующий кандидат для переключения или null, если некуда/исчерпано.
  VpnNode? nextCandidate(List<VpnNode> all, String? failedId) {
    if (!canAttempt) return null;
    final ordered = orderCandidates(all, failedId: failedId, triedIds: _triedIds);
    if (ordered.isEmpty) return null;
    return ordered.first;
  }

  /// Задержка перед попыткой с индексом [attempt] (0-based).
  Duration backoffFor(int attempt) {
    if (backoffs.isEmpty) return Duration.zero;
    final i = attempt < backoffs.length ? attempt : backoffs.length - 1;
    return backoffs[i];
  }

  /// Отметить, что попытка переключения на [nodeId] начата.
  Duration registerAttempt(String nodeId) {
    final delay = backoffFor(_attempts);
    _attempts++;
    _triedIds.add(nodeId);
    return delay;
  }

  /// Новый чистый эпизод (успешный пользовательский коннект / ручное отключение).
  void reset() {
    _attempts = 0;
    _triedIds.clear();
    userStopped = false;
  }
}

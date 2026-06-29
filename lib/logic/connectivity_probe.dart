// lib/logic/connectivity_probe.dart
//
// Логика проактивной пробы связи: пока VPN «подключён», периодически проверяем,
// что трафик реально идёт (TCP до ноды + DNS). Один-два промаха могут быть
// транзиентом, поэтому действуем только после N подряд неудач (антидребезг).
//
// Здесь — чистая логика решения (тестируемая); сетевые вызовы и таймер живут
// в AppStateBase, которая дёргает recordResult() и читает shouldAct().

class ProbeDecider {
  /// Сколько подряд неудач до того, как считать связь умершей.
  final int failureThreshold;

  int _consecutiveFailures = 0;
  bool _acted = false;

  ProbeDecider({this.failureThreshold = 2});

  int get consecutiveFailures => _consecutiveFailures;

  /// Зафиксировать результат одной пробы. true = связь жива.
  /// Возвращает true, если ИМЕННО сейчас нужно действовать
  /// (порог достигнут впервые с последнего успеха).
  bool recordResult(bool alive) {
    if (alive) {
      _consecutiveFailures = 0;
      _acted = false;
      return false;
    }
    _consecutiveFailures++;
    if (_consecutiveFailures >= failureThreshold && !_acted) {
      _acted = true; // не дёргать действие повторно на каждой следующей неудаче
      return true;
    }
    return false;
  }

  /// Сброс при дисконнекте / новом подключении.
  void reset() {
    _consecutiveFailures = 0;
    _acted = false;
  }
}

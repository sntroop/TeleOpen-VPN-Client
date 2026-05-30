// lib/state/app_state_failover.dart
//
// Авто-failover: если активный сервер не отвечает (ошибка коннекта или
// подтверждённый обрыв связи пробой), пробуем переключиться на следующий
// сервер по возрастанию пинга. Защита от петли — в FailoverController
// (cap попыток + backoff). part of app_state.

part of 'app_state.dart';

mixin AppStateFailover on AppStateBase {
  /// Все ноды из всех групп — пул кандидатов для переключения.
  List<VpnNode> get _allNodes => [for (final g in groups) ...g.nodes];

  /// Сбросить эпизод failover (вызывается при чистом пользовательском коннекте).
  void _resetFailover() => _failover.reset();

  /// Хук из пробы связи: связь подтверждённо мертва при status=connected.
  @override
  void _onConnectivityLost() {
    final id = activeNode?.id;
    if (id == null) return;
    // ignore: discarded_futures
    _tryFailover(failedId: id);
  }

  /// Точка входа: текущий сервер сдох. Пытаемся переключиться, если включено.
  /// [reason] — для лога/диагностики.
  @override
  Future<void> _tryFailover({required String failedId}) async {
    if (!settings.autoFailover) return;
    if (_failover.userStopped) return;

    final candidate = _failover.nextCandidate(_allNodes, failedId);
    if (candidate == null) {
      // некуда переключаться или попытки исчерпаны — оставляем как есть
      lastError = _failover.exhausted
          ? 'Не удалось подключиться: перебраны доступные серверы'
          : lastError;
      return;
    }

    final delay = _failover.registerAttempt(candidate.id);
    await Future.delayed(delay);

    // За время backoff пользователь мог нажать «отключить» — уважаем это.
    if (_failover.userStopped) return;
    await connect(candidate);
  }
}

// lib/state/vpn_status.dart
//
// Статус VPN-туннеля. Вынесено из main.dart при разбиении монолита.

enum VpnStatus { stopped, connecting, connected, error }

/// Результат разбора нативного статус-строки.
class NativeStatusEvent {
  final VpnStatus status;

  /// true, если это ВНЕЗАПНЫЙ обрыв (натив прислал 'DROPPED'), а не штатный
  /// стоп. По нему AppState решает, запускать ли failover.
  final bool unexpectedDrop;

  const NativeStatusEvent(this.status, {this.unexpectedDrop = false});
}

/// Чистый маппинг строки от нативки в статус + признак внезапного обрыва.
/// Натив присылает: CONNECTING / CONNECTED / STOPPED (штатный стоп) /
/// DROPPED (упал сам, не по команде пользователя).
NativeStatusEvent parseNativeStatus(String raw) {
  switch (raw.toUpperCase()) {
    case 'CONNECTING':
      return const NativeStatusEvent(VpnStatus.connecting);
    case 'CONNECTED':
      return const NativeStatusEvent(VpnStatus.connected);
    case 'DROPPED':
      // Внезапный обрыв: показываем ошибку и сигналим failover.
      return const NativeStatusEvent(VpnStatus.error, unexpectedDrop: true);
    case 'STOPPED':
    default:
      return const NativeStatusEvent(VpnStatus.stopped);
  }
}


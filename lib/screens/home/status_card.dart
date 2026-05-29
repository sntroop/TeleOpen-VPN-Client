// lib/screens/home/status_card.dart
// Карточка статуса соединения (_StatusCard) + анимированная точка (_StatusDot).
// part of home_screen.

part of '../home_screen.dart';

class _StatusCard extends StatelessWidget {
  final AppState state;
  const _StatusCard({required this.state});

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    final isConnected  = state.status == VpnStatus.connected;
    final isConnecting = state.status == VpnStatus.connecting;
    final isError      = state.status == VpnStatus.error;

    final Color statusColor;
    final String statusText;
    if (isError) {
      statusColor = c.red;
      statusText  = state.lastError ?? 'Ошибка';
    } else if (isConnected) {
      statusColor = c.green;
      statusText  = 'Подключено';
    } else if (isConnecting) {
      statusColor = c.orange;
      statusText  = 'Подключение…';
    } else {
      statusColor = c.textTertiary;
      statusText  = 'Отключено';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: IosCard(
            padding: const EdgeInsets.all(20),
            radius: IosShapes.radiusXLarge,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                _StatusDot(color: statusColor, pulse: isConnecting),
                const SizedBox(width: 10),
                Expanded(child: Text(statusText, style: t.textStyles.headline, overflow: TextOverflow.ellipsis)),
                if (isConnected)
                  Text(_formatDuration(state.connectionDuration),
                      style: t.textStyles.body.copyWith(
                          color: c.textSecondary, fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: c.fill,
                  borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
                ),
                child: Row(children: [
                  Icon(CupertinoIcons.location_fill, size: 18, color: c.textPrimary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(state.activeNode?.name ?? 'Сервер не выбран',
                           style: t.textStyles.body, overflow: TextOverflow.ellipsis),
                      if (state.activeNode != null)
                        Text(
                          '${state.activeNode!.protocolLabel} • ${state.activeNode!.address}:${state.activeNode!.port}',
                          style: t.textStyles.footnote.copyWith(color: c.textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              IosButton(
                label: isConnected
                    ? 'Отключить'
                    : isConnecting ? 'Подключение…' : 'Подключить',
                style: isConnected ? IosButtonStyle.destructive : IosButtonStyle.primary,
                loading: isConnecting,
                onPressed: state.activeNode == null && !isConnected
                    ? null
                    : () {
                        if (isConnected) {
                          state.disconnect();
                        } else if (state.activeNode != null) {
                          state.connect(state.activeNode!);
                        }
                      },
              ),
            ]),
          ),
        ),
        // Живая статистика появляется только во время сессии (виджет
        // сам отдаёт SizedBox.shrink() когда status != connected).
        const TrafficStatsWidget(),
      ],
    );
  }
}

class _StatusDot extends StatefulWidget {
  final Color color;
  final bool pulse;
  const _StatusDot({required this.color, required this.pulse});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this, duration: const Duration(seconds: 1),
  )..repeat(reverse: true);

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final scale = widget.pulse ? 1.0 + 0.3 * _ctrl.value : 1.0;
        final opacity = widget.pulse ? 0.4 + 0.6 * (1 - _ctrl.value) : 1.0;
        return Stack(alignment: Alignment.center, children: [
          if (widget.pulse)
            Transform.scale(
              scale: scale,
              child: Container(
                width: 12, height: 12,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: opacity * 0.4),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
          ),
        ]);
      },
    );
  }
}

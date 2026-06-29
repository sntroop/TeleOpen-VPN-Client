// lib/screens/home/header.dart
// Шапка экрана (_Header) и ряд быстрых действий (_ActionsRow). part of home_screen.

part of '../home_screen.dart';

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    Widget circleBtn({required IconData icon, required VoidCallback onTap}) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: c.fill, shape: BoxShape.circle),
          child: Icon(icon, size: 17, color: c.textPrimary),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('TeleOpen', style: t.textStyles.largeTitle),
              const SizedBox(height: 2),
              Text('Безопасное соединение', style: t.textStyles.subheadline.copyWith(color: c.textSecondary)),
            ]),
          ),
          // Диагностика
          circleBtn(
            icon: CupertinoIcons.waveform_path_ecg,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const DiagnosticsScreen(),
            )),
          ),
          const SizedBox(width: 6),
          // Карта мира
          circleBtn(
            icon: CupertinoIcons.map_fill,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const WorldMapScreen(),
            )),
          ),
          const SizedBox(width: 6),
          // Маркетплейс
          circleBtn(
            icon: CupertinoIcons.cube_box_fill,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const MarketScreen(),
            )),
          ),
          const SizedBox(width: 6),
          // Настройки
          circleBtn(
            icon: CupertinoIcons.settings,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const SettingsScreen(),
            )),
          ),
        ],
      ),
    );
  }
}

/// Компактные две кнопки + и WiFi (иконки вместо текста, чтобы ничего не налезало)
class _ActionsRow extends StatelessWidget {
  final AppState state;
  const _ActionsRow({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    Widget btn({required IconData icon, required String label, required VoidCallback? onTap, bool loading = false}) {
      final enabled = onTap != null;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: c.fill,
            borderRadius: IosShapes.continuous(IosShapes.radiusButton),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (loading)
              SizedBox(width: 16, height: 16, child: CupertinoActivityIndicator(color: c.textPrimary))
            else
              Icon(icon, size: 18, color: enabled ? c.textPrimary : c.textTertiary),
            const SizedBox(width: 8),
            Text(label, style: t.textStyles.subheadline.copyWith(
              color: enabled ? c.textPrimary : c.textTertiary,
              fontWeight: FontWeight.w600,
            )),
          ]),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(children: [
        Expanded(child: btn(
          icon: CupertinoIcons.add,
          label: 'Подписка',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const AddSubscriptionScreen(),
          )),
        )),
        const SizedBox(width: 10),
        Expanded(child: btn(
          icon: CupertinoIcons.wifi,
          label: state.isPinging ? 'Пинг…' : 'Пинг',
          loading: state.isPinging,
          onTap: state.isPinging ? null : state.pingAll,
        )),
      ]),
    );
  }
}

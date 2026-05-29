// lib/screens/admin/badges.dart
// Вспомогательные типы и виджеты для TeleOpen-бейджей: результат выбора,
// чип бейджа в карточке, боттом-шит выбора. part of admin_panel_screen.

part of '../admin_panel_screen.dart';

/// Результат выбора в _BadgePickerSheet
class _BadgeResult {
  final TeleOpenBadge? badge;
  final bool remove;
  const _BadgeResult({this.badge, this.remove = false});
}

/// Маленький цветной чип бейджа в admin-карточке
class _AdminBadgeChip extends StatelessWidget {
  final TeleOpenBadge badge;
  const _AdminBadgeChip({required this.badge});

  Color _fg() {
    switch (badge) {
      case TeleOpenBadge.official:  return const Color(0xFF007AFF);
      case TeleOpenBadge.verified:  return const Color(0xFF34C759);
      case TeleOpenBadge.partner:   return const Color(0xFFFF9F0A);
    }
  }

  IconData _icon() {
    switch (badge) {
      case TeleOpenBadge.official:  return CupertinoIcons.star_circle_fill;
      case TeleOpenBadge.verified:  return CupertinoIcons.checkmark_seal_fill;
      case TeleOpenBadge.partner:   return CupertinoIcons.hand_thumbsup_fill;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final fg = _fg();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(IosShapes.radiusPill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_icon(), size: 11, color: fg),
        const SizedBox(width: 4),
        Text(
          badge.label,
          style: t.textStyles.caption2.copyWith(color: fg, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

/// Боттом-шит выбора бейджа
class _BadgePickerSheet extends StatelessWidget {
  final TeleOpenBadge? current;
  const _BadgePickerSheet({this.current});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    final badges = [
      (TeleOpenBadge.official, CupertinoIcons.star_circle_fill, const Color(0xFF007AFF)),
      (TeleOpenBadge.verified, CupertinoIcons.checkmark_seal_fill, const Color(0xFF34C759)),
      (TeleOpenBadge.partner, CupertinoIcons.hand_thumbsup_fill, const Color(0xFFFF9F0A)),
    ];

    return Container(
      decoration: BoxDecoration(
        color: c.bgSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Drag handle
        Center(
          child: Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: c.separator,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Бейдж TeleOpen', style: t.textStyles.headline),
        const SizedBox(height: 4),
        Text('Бейдж отображается на карточке и поднимает подписку наверх списка.',
          style: t.textStyles.footnote.copyWith(color: c.textSecondary)),
        const SizedBox(height: 16),

        // Варианты бейджей
        ...badges.map((entry) {
          final (badge, icon, color) = entry;
          final isSelected = current == badge;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(_BadgeResult(badge: badge)),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.12) : c.fill,
                borderRadius: BorderRadius.circular(IosShapes.radiusMedium),
                border: isSelected ? Border.all(color: color.withValues(alpha: 0.4)) : null,
              ),
              child: Row(children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    badge.label,
                    style: t.textStyles.body.copyWith(
                      color: isSelected ? color : c.textPrimary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(CupertinoIcons.checkmark_circle_fill, size: 18, color: color),
              ]),
            ),
          );
        }),

        // Снять бейдж (только если бейдж установлен)
        if (current != null) ...[
          const SizedBox(height: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(const _BadgeResult(remove: true)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: c.fill,
                borderRadius: BorderRadius.circular(IosShapes.radiusMedium),
              ),
              child: Row(children: [
                Icon(CupertinoIcons.xmark_circle, size: 20, color: c.red),
                const SizedBox(width: 12),
                Text('Снять бейдж', style: t.textStyles.body.copyWith(color: c.red)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

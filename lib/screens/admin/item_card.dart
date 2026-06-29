// lib/screens/admin/item_card.dart
// Карточка подписки в модераторском списке. part of admin_panel_screen.

part of '../admin_panel_screen.dart';

class _AdminItemCard extends StatelessWidget {
  final AdminMarketItem item;
  final VoidCallback onDelete;
  final VoidCallback onToggleBan;
  final VoidCallback onEdit;
  final VoidCallback onSetBadge;
  final VoidCallback onTapDetail;

  const _AdminItemCard({
    required this.item,
    required this.onDelete,
    required this.onToggleBan,
    required this.onEdit,
    required this.onSetBadge,
    required this.onTapDetail,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return IosCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Иконка + название + автор
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: onTapDetail,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: c.fill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.separator),
              ),
              clipBehavior: Clip.antiAlias,
              child: item.iconUrl.isNotEmpty
                  ? Image.network(item.iconUrl, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(CupertinoIcons.antenna_radiowaves_left_right, size: 22, color: c.textTertiary))
                  : Icon(CupertinoIcons.antenna_radiowaves_left_right, size: 22, color: c.textTertiary),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTapDetail,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.name, style: t.textStyles.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [
                  Text(
                    item.author.displayName,
                    style: t.textStyles.footnote.copyWith(color: c.textSecondary),
                  ),
                  if (item.authorPublishBanned) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('БАН', style: t.textStyles.caption2.copyWith(color: c.red, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
                const SizedBox(height: 2),
                Text(
                  '${item.nodesCount} серв. · ${item.getsCount} получ. · ★${item.ratingAvg.toStringAsFixed(1)}',
                  style: t.textStyles.caption2.copyWith(color: c.textTertiary),
                ),
                // TeleOpen badge indicator
                if (item.teleOpenBadge != null) ...[
                  const SizedBox(height: 4),
                  _AdminBadgeChip(badge: item.teleOpenBadge!),
                ],
              ]),
            ),
          ),
        ]),

        const SizedBox(height: 12),

        // Кнопки действий
        Row(children: [
          Expanded(
            child: IosButton(
              label: 'Изменить',
              style: IosButtonStyle.secondary,
              leadingIcon: CupertinoIcons.pencil,
              onPressed: onEdit,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: IosButton(
              label: item.authorPublishBanned ? 'Разбанить' : 'Забанить',
              style: item.authorPublishBanned ? IosButtonStyle.secondary : IosButtonStyle.secondary,
              leadingIcon: item.authorPublishBanned ? CupertinoIcons.checkmark_shield : CupertinoIcons.hand_raised,
              onPressed: onToggleBan,
            ),
          ),
          const SizedBox(width: 8),
          IosButton(
            label: '',
            style: IosButtonStyle.secondary,
            leadingIcon: item.teleOpenBadge != null
                ? CupertinoIcons.checkmark_seal_fill
                : CupertinoIcons.checkmark_seal,
            onPressed: onSetBadge,
          ),
          const SizedBox(width: 8),
          IosButton(
            label: '',
            style: IosButtonStyle.destructive,
            leadingIcon: CupertinoIcons.trash,
            onPressed: onDelete,
          ),
        ]),
      ]),
    );
  }
}

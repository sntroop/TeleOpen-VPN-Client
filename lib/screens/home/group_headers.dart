// lib/screens/home/group_headers.dart
// Заголовки групп: VPN-группа (трафик/срок/сворачивание) и MTProto-группа.
// part of home_screen.

part of '../home_screen.dart';

// ── Group Header with traffic info + collapse ─────────────────────────────────
class _GroupHeader extends StatelessWidget {
  final VpnGroup group;
  final VoidCallback? onRefresh;
  final VoidCallback onDelete;
  final VoidCallback onToggleCollapse;

  const _GroupHeader({
    required this.group,
    required this.onDelete,
    required this.onToggleCollapse,
    this.onRefresh,
  });

  String _fmtBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
  }

  String _fmtDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    final isUnlimited = group.trafficTotal == 0;
    final hasTraffic = group.trafficUsed != null && group.trafficTotal != null;
    final hasExpiry  = group.expiresAt != null;
    final hasExtra   = hasTraffic || hasExpiry || group.description != null;
    final fraction   = group.trafficFraction;
    final daysLeft   = group.daysLeft;

    // цвет прогресс-бара по остатку
    Color barColor = c.green;
    if (!isUnlimited && fraction != null) {
      if (fraction > 0.9) {
        barColor = c.red;
      } else if (fraction > 0.7) {
        barColor = c.orange;
      }
    }
    if (daysLeft != null && daysLeft <= 3) {
      barColor = c.red;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggleCollapse,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: IosCard(
          radius: IosShapes.radiusLarge,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── строка заголовка ──────────────────────────────────────────
              Row(children: [
                // иконка сворачивания
                AnimatedRotation(
                  turns: group.isCollapsed ? -0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(CupertinoIcons.chevron_down, size: 14, color: c.textSecondary),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    group.title,
                    style: t.textStyles.subheadline
                        .copyWith(fontWeight: FontWeight.w600, color: c.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                // кол-во серверов
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.fill,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${group.nodes.length}',
                    style: t.textStyles.caption1.copyWith(color: c.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                // refresh
                if (onRefresh != null)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onRefresh,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(CupertinoIcons.refresh, size: 16, color: c.textSecondary),
                    ),
                  ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onDelete,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(CupertinoIcons.trash, size: 16, color: c.textSecondary),
                  ),
                ),
              ]),

              // ── описание ─────────────────────────────────────────────────
              if (group.description != null) ...[
                const SizedBox(height: 6),
                Text(
                  group.description!,
                  style: t.textStyles.footnote.copyWith(color: c.textSecondary),
                ),
              ],

              // ── трафик + истечение ────────────────────────────────────────
              if (hasExtra) ...[
                const SizedBox(height: 10),
                // прогресс-бар трафика
                if (hasTraffic) ...[
                  // для безлимитного трафика (total=0) не показываем полоску
                  if (!isUnlimited) ...[
                    Row(children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: fraction,
                            minHeight: 5,
                            backgroundColor: c.fill,
                            valueColor: AlwaysStoppedAnimation<Color>(barColor),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 5),
                  ],
                  Row(children: [
                    Text(
                      isUnlimited
                          ? '${_fmtBytes(group.trafficUsed!)} / ∞'
                          : '${_fmtBytes(group.trafficUsed!)} / ${_fmtBytes(group.trafficTotal!)}',
                      style: t.textStyles.caption1.copyWith(color: c.textSecondary),
                    ),
                    const Spacer(),
                    if (hasExpiry)
                      Row(children: [
                        Icon(CupertinoIcons.calendar, size: 11, color: daysLeft != null && daysLeft <= 7 ? c.red : c.textTertiary),
                        const SizedBox(width: 3),
                        Text(
                          daysLeft != null && daysLeft <= 0
                              ? 'Истекло'
                              : daysLeft != null && daysLeft <= 30
                                  ? 'Ещё $daysLeft дн.'
                                  : _fmtDate(group.expiresAt!),
                          style: t.textStyles.caption1.copyWith(
                            color: daysLeft != null && daysLeft <= 7 ? c.red : c.textTertiary,
                          ),
                        ),
                      ]),
                  ]),
                ] else if (hasExpiry) ...[
                  // только дата истечения без трафика
                  Row(children: [
                    Icon(CupertinoIcons.calendar, size: 12, color: daysLeft != null && daysLeft <= 7 ? c.red : c.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      'Истекает: ${_fmtDate(group.expiresAt!)}${daysLeft != null && daysLeft >= 0 ? ' · ещё $daysLeft дн.' : ''}',
                      style: t.textStyles.caption1.copyWith(
                        color: daysLeft != null && daysLeft <= 7 ? c.red : c.textTertiary,
                      ),
                    ),
                  ]),
                ],

                // время обновления
                if (group.updatedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Обновлено ${_fmtDate(group.updatedAt!)}',
                    style: t.textStyles.caption2.copyWith(color: c.textTertiary),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── MTProto Group Header ──────────────────────────────────────────────────────
class _MtProtoGroupHeader extends StatelessWidget {
  final MtProtoProxyGroup group;
  final VoidCallback onDelete;
  final VoidCallback onToggleCollapse;
  final VoidCallback onShare;

  const _MtProtoGroupHeader({
    required this.group,
    required this.onDelete,
    required this.onToggleCollapse,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggleCollapse,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: IosCard(
          radius: IosShapes.radiusLarge,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(children: [
            AnimatedRotation(
              turns: group.isCollapsed ? -0.25 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(CupertinoIcons.chevron_down, size: 14, color: c.textSecondary),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                group.title,
                style: t.textStyles.subheadline
                    .copyWith(fontWeight: FontWeight.w600, color: c.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: c.fill,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${group.proxies.length}',
                style: t.textStyles.caption1.copyWith(color: c.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onShare,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(CupertinoIcons.share, size: 16, color: c.textSecondary),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDelete,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(CupertinoIcons.trash, size: 16, color: c.textSecondary),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

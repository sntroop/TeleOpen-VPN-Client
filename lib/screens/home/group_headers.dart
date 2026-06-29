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
  final VoidCallback? onSort;
  final bool sortActive;

  const _GroupHeader({
    required this.group,
    required this.onDelete,
    required this.onToggleCollapse,
    this.onRefresh,
    this.onSort,
    this.sortActive = false,
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

  /// Акцент бренда продавца ('#RRGGBB' / '#AARRGGBB') → Color, либо null.
  Color? _brandColor() {
    final s = group.brandColor;
    if (s == null || s.isEmpty) return null;
    var hex = s.replaceFirst('#', '').trim();
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    final v = int.tryParse(hex, radix: 16);
    return v == null ? null : Color(v);
  }

  /// Открывает диплинк «Продлить» (renew_url) во внешнем приложении (бот продавца).
  Future<void> _openRenew() async {
    final url = group.renewUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Нормализует contact-ссылку автора (t.me/..., @user, https://t.me/...) в https-URL.
  String? _contactUri() {
    var s = group.contactUrl?.trim();
    if (s == null || s.isEmpty) return null;
    if (s.startsWith('@')) {
      s = 'https://t.me/${s.substring(1)}';
    } else if (s.startsWith('t.me/')) {
      s = 'https://$s';
    } else if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://t.me/$s';
    }
    return s;
  }

  /// Открывает контакт автора/канала во внешнем приложении (Telegram/браузер).
  Future<void> _openContact() async {
    final s = _contactUri();
    if (s == null) return;
    final uri = Uri.tryParse(s);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    final brand = _brandColor();
    final hasRenew = group.renewUrl != null && group.renewUrl!.isNotEmpty;
    final hasLogo = group.iconUrl != null && group.iconUrl!.isNotEmpty;
    final hasContact = _contactUri() != null;
    final hasDescription = group.description != null && group.description!.isNotEmpty;

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

    final accent = brand ?? c.blue;
    Widget contactBtn() => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openContact,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(CupertinoIcons.paperplane_fill, size: 13, color: accent),
              const SizedBox(width: 5),
              Text(
                'Contact',
                style: t.textStyles.caption1
                    .copyWith(color: accent, fontWeight: FontWeight.w600),
              ),
            ]),
          ),
        );

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
                // акцент бренда продавца (teleopen://)
                if (brand != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: brand, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                ],
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
                // сортировка серверов этой группы
                if (onSort != null)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onSort,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(CupertinoIcons.arrow_up_arrow_down,
                          size: 16, color: sortActive ? c.blue : c.textSecondary),
                    ),
                  ),
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

              // ── лого + описание ──────────────────────────────────────────
              if (hasLogo) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // круглый логотип автора + кнопка Contact под ним
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: Image.network(
                            group.iconUrl!,
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(color: c.fill, shape: BoxShape.circle),
                              child: Icon(CupertinoIcons.photo, size: 22, color: c.textTertiary),
                            ),
                          ),
                        ),
                        if (hasContact) ...[
                          const SizedBox(height: 8),
                          contactBtn(),
                        ],
                      ],
                    ),
                    const SizedBox(width: 14),
                    // описание справа от логотипа
                    Expanded(
                      child: hasDescription
                          ? Text(
                              group.description!,
                              style: t.textStyles.footnote.copyWith(color: c.textSecondary),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ] else ...[
                // нет логотипа — описание остаётся как раньше (на всю ширину)
                if (hasDescription) ...[
                  const SizedBox(height: 6),
                  Text(
                    group.description!,
                    style: t.textStyles.footnote.copyWith(color: c.textSecondary),
                  ),
                ],
                if (hasContact) ...[
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerLeft, child: contactBtn()),
                ],
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

              // ── кнопка «Продлить» (renew_url из teleopen://) ──────────────
              if (hasRenew) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openRenew,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: (brand ?? c.blue).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(CupertinoIcons.arrow_clockwise_circle,
                          size: 15, color: brand ?? c.blue),
                      const SizedBox(width: 6),
                      Text(
                        'Продлить',
                        style: t.textStyles.footnote.copyWith(
                          color: brand ?? c.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ]),
                  ),
                ),
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

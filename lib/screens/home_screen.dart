import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ios_theme.dart';
import '../main.dart';
import '../models/vpn_node.dart';
import '../models/mtproto_proxy.dart';
import '../logic/telegram_proxy.dart';
import '../logic/ping.dart';
import '../widgets/telegram_proxy_sheet.dart';
import 'settings_screen.dart';
import 'add_subscription_screen.dart';
import 'share_screen.dart';
import 'market_screen.dart';
import 'world_map_screen.dart';
import 'diagnostics_screen.dart';
import 'speed_test_screen.dart';
import '../widgets/traffic_stats_widget.dart';
import '../widgets/update_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _filterIndex = 0;
  final ScrollController _scrollCtrl = ScrollController();
  bool _showScrollTop = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Показываем кнопку когда проскроллили больше 300px (кнопка «Подключить» уже не видна)
    final show = _scrollCtrl.offset > 300;
    if (show != _showScrollTop) setState(() => _showScrollTop = show);
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final state = AppStateScope.of(context);

    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            CustomScrollView(
              cacheExtent: 2000, controller: _scrollCtrl,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            // Баннер «Доступна новая версия» — сам решает, рисоваться ему
            // или нет. Если апдейта нет, отдаёт SizedBox.shrink().
            const SliverToBoxAdapter(child: UpdateBanner()),
            SliverToBoxAdapter(child: _Header()),
            SliverToBoxAdapter(child: _StatusCard(state: state)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
                child: Row(children: [
                  Text('Серверы', style: t.textStyles.title2),
                  const Spacer(),
                  IosSegment(
                    activeIndex: _filterIndex,
                    onChanged: (i) => setState(() => _filterIndex = i),
                    items: const [
                      IosSegmentItem('Все'),
                      IosSegmentItem('Избранное'),
                    ],
                  ),
                ]),
              ),
            ),
            SliverToBoxAdapter(child: _ActionsRow(state: state)),
            ..._buildGroups(context, state),
            ..._buildMtProtoGroups(context, state),
            SliverToBoxAdapter(child: SizedBox(height: MediaQuery.of(context).padding.bottom + 24)),
          ],
        ),
            // Кнопка «наверх»
            Positioned(
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 16,
              child: AnimatedScale(
                scale: _showScrollTop ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                child: AnimatedOpacity(
                  opacity: _showScrollTop ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: GestureDetector(
                    onTap: () => _scrollCtrl.animateTo(0,
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic),
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: c.blue,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: c.blue.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: const Icon(CupertinoIcons.arrow_up, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroups(BuildContext context, AppState state) {
    final t = IosTheme.of(context);
    final c = t.colors;

    if (state.groups.isEmpty) {
      return [
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 40, 16, 40),
          child: Center(
            child: Column(children: [
              Icon(CupertinoIcons.cloud_download, size: 48, color: c.textTertiary),
              const SizedBox(height: 12),
              Text('Нет добавленных серверов', style: t.textStyles.body.copyWith(color: c.textSecondary)),
              const SizedBox(height: 4),
              Text(
                'Нажмите «+» сверху, чтобы добавить подписку',
                style: t.textStyles.footnote.copyWith(color: c.textTertiary),
              ),
            ]),
          ),
        )),
      ];
    }

    final widgets = <Widget>[];
    for (final g in state.groups) {
      var nodes = g.nodes;
      if (_filterIndex == 1) {
        nodes = nodes.where((n) => n.isFavorite).toList();
      }
      if (nodes.isEmpty && _filterIndex == 1) continue;

      widgets.add(SliverToBoxAdapter(
        child: _GroupHeader(
          group: g,
          onRefresh: g.sourceUrl != null
              ? () => _refreshGroup(context, state, g)
              : null,
          onDelete: () => _confirmDeleteGroup(context, state, g),
          onToggleCollapse: () => setState(() => g.isCollapsed = !g.isCollapsed),
        ),
      ));

      if (nodes.isNotEmpty && !g.isCollapsed) {
        widgets.add(SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.separated(
            itemCount: nodes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _ServerTile(key: ValueKey(nodes[i].id), node: nodes[i], state: state),
            addRepaintBoundaries: true,
            addAutomaticKeepAlives: false,
          ),
        ));
      }
    }

    if (widgets.isEmpty) {
      widgets.add(SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 40, 16, 40),
        child: Center(
          child: Column(children: [
            Icon(CupertinoIcons.star, size: 48, color: c.textTertiary),
            const SizedBox(height: 12),
            Text('Нет избранных серверов', style: t.textStyles.body.copyWith(color: c.textSecondary)),
          ]),
        ),
      )));
    }

    return widgets;
  }

  List<Widget> _buildMtProtoGroups(BuildContext context, AppState state) {
    final mtGroups = state.mtProtoGroups;
    if (mtGroups.isEmpty) return [];

    final t = IosTheme.of(context);
    final widgets = <Widget>[];

    widgets.add(SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
        child: Text('MTProto-прокси', style: t.textStyles.title2),
      ),
    ));

    for (final g in mtGroups) {
      widgets.add(SliverToBoxAdapter(
        child: _MtProtoGroupHeader(
          group: g,
          onDelete: () => _confirmDeleteMtProtoGroup(context, state, g),
          onToggleCollapse: () => setState(() => g.isCollapsed = !g.isCollapsed),
          onShare: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ShareScreen(initialMtProtoGroup: g),
          )),
        ),
      ));

      if (g.proxies.isNotEmpty && !g.isCollapsed) {
        widgets.add(SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          sliver: SliverList.separated(
            itemCount: g.proxies.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _MtProtoTile(
              key: ValueKey('${g.id}_$i'),
              group: g,
              proxy: g.proxies[i],
              state: state,
            ),
          ),
        ));
      }
    }

    return widgets;
  }

  Future<void> _confirmDeleteMtProtoGroup(BuildContext context, AppState state, MtProtoProxyGroup g) async {
    await IosDialog.show<bool>(
      context,
      IosDialog(
        title: 'Удалить группу?',
        description: '«${g.title}» и все её прокси будут удалены.',
        actions: [
          IosButton(
            label: 'Удалить',
            style: IosButtonStyle.destructive,
            onPressed: () {
              state.removeMtProtoGroup(g.id);
              Navigator.of(context).pop(true);
            },
          ),
          IosButton(
            label: 'Отмена',
            style: IosButtonStyle.secondary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshGroup(BuildContext context, AppState state, VpnGroup g) async {
    final err = await state.refreshSubscription(g);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err ?? '${g.title} обновлена'),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _confirmDeleteGroup(BuildContext context, AppState state, VpnGroup g) async {
    await IosDialog.show<bool>(
      context,
      IosDialog(
        title: 'Удалить подписку?',
        description: '«${g.title}» и все её серверы будут удалены.',
        actions: [
          IosButton(
            label: 'Удалить',
            style: IosButtonStyle.destructive,
            onPressed: () {
              state.removeGroup(g.id);
              Navigator.of(context).pop(true);
            },
          ),
          IosButton(
            label: 'Отмена',
            style: IosButtonStyle.secondary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}

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
      } else if (fraction > 0.7) barColor = c.orange;
    }
    if (daysLeft != null && daysLeft <= 3) barColor = c.red;

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

/// Тайл сервера. Tap = выбрать/подключить. Long-press = меню (Удалить).
class _ServerTile extends StatefulWidget {
  final VpnNode node;
  final AppState state;
  const _ServerTile({super.key, required this.node, required this.state});

  @override
  State<_ServerTile> createState() => _ServerTileState();
}

class _ServerTileState extends State<_ServerTile> with SingleTickerProviderStateMixin {
  late final AnimationController _swipeCtrl;
  double _dragExtent = 0;
  bool _dragActivated = false;
  static const double _actionWidth = 72;
  static const double _deadZone = 20;  // минимальный свайп чтобы начать сдвиг
  static const double _rightThreshold = _actionWidth * 2;
  static const double _leftThreshold = _actionWidth;

  VpnNode get node => widget.node;
  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _swipeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _swipeCtrl.addListener(() {
      if (_swipeCtrl.isAnimating) setState(() {});
    });
  }

  @override
  void dispose() {
    _swipeCtrl.dispose();
    super.dispose();
  }

  void _onHorizontalDragStart(DragStartDetails d) {
    _dragActivated = false;
    _dragStartX = d.localPosition.dx;
  }

  double _dragStartX = 0;

  void _onHorizontalDragUpdate(DragUpdateDetails d) {
    final totalDelta = (d.localPosition.dx - _dragStartX).abs();
    if (!_dragActivated) {
      if (totalDelta < _deadZone) return;
      _dragActivated = true;
    }
    setState(() {
      _dragExtent += d.primaryDelta!;
      _dragExtent = _dragExtent.clamp(-_rightThreshold - 20, _leftThreshold + 20);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails d) {
    if (!_dragActivated) {
      _dragActivated = false;
      return;
    }
    _dragActivated = false;

    double target = 0;
    if (_dragExtent < -_rightThreshold * 0.4) {
      target = -_rightThreshold;
    } else if (_dragExtent > _leftThreshold * 0.4) {
      target = _leftThreshold;
    }
    final start = _dragExtent;
    final tween = Tween<double>(begin: start, end: target);
    _swipeCtrl.reset();
    _swipeCtrl.addListener(() {
      _dragExtent = tween.evaluate(CurvedAnimation(parent: _swipeCtrl, curve: Curves.easeOutCubic));
    });
    _swipeCtrl.forward();
  }

  void _resetSwipe() {
    final start = _dragExtent;
    final tween = Tween<double>(begin: start, end: 0.0);
    _swipeCtrl.reset();
    _swipeCtrl.addListener(() {
      _dragExtent = tween.evaluate(CurvedAnimation(parent: _swipeCtrl, curve: Curves.easeOutCubic));
    });
    _swipeCtrl.forward();
  }

  // ВНИМАНИЕ: НЕ переопределяй здесь operator == и hashCode.
  // Раньше тут было сравнение по node.pingMs / node.isFavorite, но т.к. VpnNode
  // мутируется на месте (новый виджет ссылается на тот же объект), сравнение
  // всегда давало true → Flutter скипал rebuild → визуально звёздочка и пинг
  // не обновлялись, хотя данные менялись. Без кастомного == всё работает само.

  Color _pingColor(int? ms, IosColors c) {
    if (ms == null) return c.textTertiary;
    if (ms < 100) return c.green;
    if (ms < 250) return c.orange;
    return c.red;
  }

  void _showActions(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        margin: EdgeInsets.fromLTRB(8, 0, 8, MediaQuery.of(context).padding.bottom + 8),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: c.bgSecondary,
          borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 6),
            width: 36, height: 4,
            decoration: BoxDecoration(color: c.textQuaternary, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(children: [
              Text(node.name, style: t.textStyles.headline, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
          IosListTile(
            leadingIcon: CupertinoIcons.info_circle,
            leadingIconBg: c.fill,
            title: 'О сервере',
            onTap: () {
              Navigator.of(context).pop();
              _showServerInfo(context);
            },
          ),
          Container(margin: const EdgeInsets.only(left: 54), height: 0.5, color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.pencil,
            leadingIconBg: c.fill,
            title: 'Переименовать',
            onTap: () {
              Navigator.of(context).pop();
              _showRenameDialog(context, state, node);
            },
          ),
          Container(margin: const EdgeInsets.only(left: 54), height: 0.5, color: c.separator),
          IosListTile(
            leadingIcon: node.isFavorite ? CupertinoIcons.star_slash : CupertinoIcons.star_fill,
            leadingIconBg: c.fill,
            title: node.isFavorite ? 'Убрать из избранного' : 'В избранное',
            onTap: () { state.toggleFavorite(node); Navigator.of(context).pop(); },
          ),
          Container(margin: const EdgeInsets.only(left: 54), height: 0.5, color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.wifi,
            leadingIconBg: c.fill,
            title: 'Пингануть',
            onTap: () { state.pingOne(node); Navigator.of(context).pop(); },
          ),
          Container(margin: const EdgeInsets.only(left: 54), height: 0.5, color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.waveform_path_ecg,
            leadingIconBg: c.fill,
            title: 'Диагностика',
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DiagnosticsScreen(initialNode: node),
              ));
            },
          ),
          Container(margin: const EdgeInsets.only(left: 54), height: 0.5, color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.rocket_fill,
            leadingIconBg: c.fill,
            title: 'Тест скорости',
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(CupertinoPageRoute(
                builder: (_) => SpeedTestScreen(node: node),
              ));
            },
          ),
          Container(margin: const EdgeInsets.only(left: 54), height: 0.5, color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.share,
            leadingIconBg: c.fill,
            title: 'Поделиться группой',
            onTap: () {
              Navigator.of(context).pop();
              final g = AppStateScope.of(context, listen: false).groups
                  .where((gr) => gr.id == node.groupId).cast<VpnGroup?>().firstOrNull;
              if (g != null) {
                Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ShareScreen(group: g),
              ));
              }
            },
          ),
          Container(margin: const EdgeInsets.only(left: 54), height: 0.5, color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.trash,
            leadingIconBg: c.red,
            title: 'Удалить сервер',
            titleColor: c.red,
            onTap: () {
              state.removeNode(node);
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 8),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  void _showServerInfo(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    // Парсим JSON из rawUri/params для отображения как в Happ
    final network = node.params['type'] ?? node.params['network'] ?? 'tcp';
    final security = node.params['security'] ?? (node.protocol == VpnProtocol.trojan ? 'tls' : 'none');
    final sni = node.params['sni'] ?? node.params['peer'] ?? node.address;
    final fp = node.params['fp'] ?? node.params['fingerprint'] ?? '';
    final flow = node.params['flow'] ?? '';
    final alpn = node.params['alpn'] ?? '';
    final pbk = node.params['pbk'] ?? '';
    final sid = node.params['sid'] ?? '';

    // Формируем JSON данные сервера как в Happ
    const excludedKeys = ['type', 'network', 'security', 'sni', 'peer',
                           'fp', 'fingerprint', 'flow', 'alpn', 'pbk',
                           'sid', 'inbound_port'];
    final extraParams = Map<String, dynamic>.fromEntries(
      node.params.entries.where((e) => !excludedKeys.contains(e.key)),
    );
    final jsonData = <String, dynamic>{
      'name': node.name,
      'address': node.address,
      'port': node.port,
      'protocol': node.protocolLabel,
      if (network.isNotEmpty && network != 'tcp') 'network': network,
      if (security.isNotEmpty && security != 'none') 'security': security,
      if (sni.isNotEmpty && sni != node.address) 'sni': sni,
      if (fp.isNotEmpty) 'fingerprint': fp,
      if (flow.isNotEmpty) 'flow': flow,
      if (alpn.isNotEmpty) 'alpn': alpn,
      if (pbk.isNotEmpty) 'publicKey': pbk,
      if (sid.isNotEmpty) 'shortId': sid,
      ...extraParams,
    };

    const encoder = JsonEncoder.withIndent('  ');
    final jsonText = encoder.convert(jsonData);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollController) => Container(
          margin: EdgeInsets.fromLTRB(8, 0, 8, MediaQuery.of(context).padding.bottom + 8),
          decoration: BoxDecoration(
            color: c.bgSecondary,
            borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 6),
              width: 36, height: 4,
              decoration: BoxDecoration(color: c.textQuaternary, borderRadius: BorderRadius.circular(2)),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('О сервере', style: t.textStyles.headline),
                    const SizedBox(height: 2),
                    Text(
                      node.protocolLabel,
                      style: t.textStyles.footnote.copyWith(color: c.textSecondary),
                    ),
                  ]),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(color: c.fill, shape: BoxShape.circle),
                    child: Icon(CupertinoIcons.xmark, size: 14, color: c.textSecondary),
                  ),
                ),
              ]),
            ),
            // Info rows
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  // Основная информация
                  _InfoSection(title: 'Основное', c: c, t: t, rows: [
                    _InfoRow('Название', _stripFlag(node.name), c, t),
                    _InfoRow('Адрес', node.address, c, t),
                    _InfoRow('Порт', '${node.port}', c, t),
                    _InfoRow('Протокол', node.protocolLabel, c, t),
                    if (node.pingMs != null)
                      _InfoRow('Пинг', '${node.pingMs} ms', c, t,
                          valueColor: node.pingMs! < 100 ? c.green : node.pingMs! < 250 ? c.orange : c.red),
                  ]),
                  const SizedBox(height: 12),
                  // Настройки подключения
                  if (network.isNotEmpty || security.isNotEmpty || sni.isNotEmpty || fp.isNotEmpty)
                    _InfoSection(title: 'Подключение', c: c, t: t, rows: [
                      if (network.isNotEmpty) _InfoRow('Network', network, c, t),
                      if (security.isNotEmpty && security != 'none') _InfoRow('Security', security, c, t),
                      if (sni.isNotEmpty && sni != node.address) _InfoRow('SNI', sni, c, t),
                      if (fp.isNotEmpty) _InfoRow('Fingerprint', fp, c, t),
                      if (flow.isNotEmpty) _InfoRow('Flow', flow, c, t),
                      if (alpn.isNotEmpty) _InfoRow('ALPN', alpn, c, t),
                      if (pbk.isNotEmpty) _InfoRow('Public Key', pbk, c, t),
                      if (sid.isNotEmpty) _InfoRow('Short ID', sid, c, t),
                    ]),
                  const SizedBox(height: 12),
                  // JSON данные как в Happ
                  Text(
                    'Json данные',
                    style: t.textStyles.subheadline.copyWith(
                      color: c.blue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.bgPrimary,
                      borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
                    ),
                    child: SelectableText(
                      jsonText,
                      style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 11.5,
                        color: c.textSecondary,
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Кнопка копировать URI
                  IosButton(
                    label: 'Копировать URI',
                    style: IosButtonStyle.secondary,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: node.rawUri));
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('URI скопирован'),
                        duration: Duration(seconds: 2),
                      ));
                    },
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final isActive = state.activeNode?.id == node.id;
    final isConnected = isActive && state.status == VpnStatus.connected;

    // Swipe action кнопка
    Widget actionBtn({required IconData icon, required String label, required Color bg, required VoidCallback onTap}) {
      return GestureDetector(
        onTap: () { _resetSwipe(); onTap(); },
        child: Container(
          alignment: Alignment.center,
          color: bg,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
    }

    final card = IosCard(
        onTap: () { _resetSwipe(); state.setActiveOnly(node); },
        onLongPress: () => _showActions(context),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        radius: IosShapes.radiusLarge,
        border: isActive
            ? Border.all(
                color: isConnected ? c.green : c.blue,
                width: 1.5,
              )
            : null,
        backgroundColor: isActive
            ? (isConnected
                ? c.green.withValues(alpha: 0.07)
                : c.blue.withValues(alpha: 0.07))
            : null,
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: isConnected ? c.green.withValues(alpha: 0.15) : c.fill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: Text(_flag(node.name), style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_stripFlag(node.name), style: t.textStyles.body, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Row(children: [
                Text(node.protocolLabel,
                    style: t.textStyles.caption2.copyWith(color: c.textTertiary, letterSpacing: 0.5)),
                const SizedBox(width: 6),
                Container(width: 3, height: 3, decoration: BoxDecoration(color: c.textTertiary, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                if (node.pingMs != null)
                  Text(
                    '${node.pingMs} ms',
                    style: t.textStyles.caption1.copyWith(color: _pingColor(node.pingMs, c)),
                  ),
              ]),
            ]),
          ),
          // Кнопка быстрого пинга (спидометр)
          _TileButton(
            icon: CupertinoIcons.wifi,
            onTap: () => state.pingOne(node),
            color: c.textTertiary,
          ),
          // Звёздочка
          _TileButton(
            icon: node.isFavorite ? CupertinoIcons.star_fill : CupertinoIcons.star,
            onTap: () => state.toggleFavorite(node),
            color: node.isFavorite ? c.yellow : c.textTertiary,
          ),
          const SizedBox(width: 2),
          // Стрелочка / зелёная точка
          if (isConnected)
            Container(width: 8, height: 8, decoration: BoxDecoration(color: c.green, shape: BoxShape.circle))
          else
            _TileButton(
              icon: CupertinoIcons.chevron_right,
              onTap: () => _showActions(context),
              color: c.textTertiary,
              size: 14,
            ),
        ]),
    );

    return GestureDetector(
      onHorizontalDragStart: _onHorizontalDragStart,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      child: ClipRRect(
        borderRadius: IosShapes.continuous(IosShapes.radiusLarge),
        child: IntrinsicHeight(
          child: Stack(children: [
            // ─── Правая сторона (свайп влево → видны справа) ───
            if (_dragExtent < -16)
            Positioned(
              top: 0, bottom: 0, right: 0,
              width: _rightThreshold,
              child: Row(children: [
                Expanded(child: actionBtn(
                  icon: CupertinoIcons.share,
                  label: 'Поделиться',
                  bg: c.blue,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: node.rawUri));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('URI скопирован'),
                      duration: Duration(seconds: 2),
                    ));
                  },
                )),
                Expanded(child: actionBtn(
                  icon: CupertinoIcons.trash_fill,
                  label: 'Удалить',
                  bg: c.red,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    state.removeNode(node);
                  },
                )),
              ]),
            ),
            // ─── Левая сторона (свайп вправо → видна слева) ───
            if (_dragExtent > 16)
            Positioned(
              top: 0, bottom: 0, left: 0,
              width: _leftThreshold,
              child: actionBtn(
                icon: CupertinoIcons.bolt_fill,
                label: 'Коннект',
                bg: c.green,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  state.setActiveOnly(node);
                  state.connect(node);
                },
              ),
            ),
            // ─── Карточка со сдвигом ───
            Transform.translate(
              offset: Offset(_dragExtent, 0),
              child: card,
            ),
          ]),
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, AppState state, VpnNode node) {
    final ctrl = TextEditingController(text: node.name);
    final t = IosTheme.of(context);
    final c = t.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          margin: EdgeInsets.fromLTRB(8, 0, 8, MediaQuery.of(context).padding.bottom + 8),
          decoration: BoxDecoration(
            color: c.bgSecondary,
            borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 6),
              width: 36, height: 4,
              decoration: BoxDecoration(color: c.textQuaternary, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text('Переименовать', style: t.textStyles.headline),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: IosField(
                controller: ctrl,
                label: 'Новое название',
                placeholder: node.name,
                autofocus: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(children: [
                Expanded(child: IosButton(
                  label: 'Отмена',
                  style: IosButtonStyle.secondary,
                  onPressed: () => Navigator.of(context).pop(),
                )),
                const SizedBox(width: 10),
                Expanded(child: IosButton(
                  label: 'Сохранить',
                  style: IosButtonStyle.primary,
                  onPressed: () {
                    final newName = ctrl.text.trim();
                    if (newName.isNotEmpty) state.renameNode(node, newName);
                    Navigator.of(context).pop();
                  },
                )),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  String _flag(String name) {
    final runes = name.runes.toList();
    if (runes.isEmpty) return '🌐';
    if (runes.length >= 2 &&
        runes[0] >= 0x1F1E6 && runes[0] <= 0x1F1FF &&
        runes[1] >= 0x1F1E6 && runes[1] <= 0x1F1FF) {
      return String.fromCharCodes([runes[0], runes[1]]);
    }
    return '🌐';
  }

  String _stripFlag(String name) {
    final flag = _flag(name);
    if (name.startsWith(flag)) return name.substring(flag.length).trim();
    return name;
  }
}

// ── Вспомогательные виджеты для экрана "О сервере" ───────────────────────────

class _InfoSection extends StatelessWidget {
  final String title;
  final IosColors c;
  final IosThemeData t;
  final List<Widget> rows;

  const _InfoSection({required this.title, required this.c, required this.t, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        title,
        style: t.textStyles.subheadline.copyWith(
          color: c.blue,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: c.bgPrimary,
          borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: rows),
      ),
    ]);
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IosColors c;
  final IosThemeData t;
  final Color? valueColor;

  const _InfoRow(this.label, this.value, this.c, this.t, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Text(label, style: t.textStyles.footnote.copyWith(color: c.textSecondary)),
        const Spacer(),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            style: t.textStyles.footnote.copyWith(
              color: valueColor ?? c.textPrimary,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}

// ── Кнопка-иконка внутри тайла (корректно работает рядом с onLongPress) ───────
class _TileButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final double size;

  const _TileButton({
    required this.icon,
    required this.onTap,
    required this.color,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // opaque — гарантируем, что тап на эту зону НЕ улетит в родительский
      // GestureDetector карточки (который теперь deferToChild)
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        // увеличена тап-зона, чтобы попадать пальцем по иконке размером 16
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Icon(icon, size: size, color: color),
      ),
    );
  }
}

// ── MTProto Proxy Tile ────────────────────────────────────────────────────────
class _MtProtoTile extends StatefulWidget {
  final MtProtoProxyGroup group;
  final MtProtoProxy proxy;
  final AppState state;

  const _MtProtoTile({
    super.key,
    required this.group,
    required this.proxy,
    required this.state,
  });

  @override
  State<_MtProtoTile> createState() => _MtProtoTileState();
}

class _MtProtoTileState extends State<_MtProtoTile> {
  Color _pingColor(int? ms, IosColors c) {
    if (ms == null) return c.textTertiary;
    if (ms < 100) return c.green;
    if (ms < 250) return c.orange;
    return c.red;
  }

  Future<void> _pingOne() async {
    final ms = await MtProtoProxyPinger.pingOne(widget.proxy);
    if (!mounted) return;
    setState(() => widget.proxy.pingMs = ms);
    widget.state.persistMtProtoGroups();
  }

  void _shareProxy(BuildContext context) {
    final link = widget.proxy.buildLink(https: true);
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ссылка скопирована'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showRenameDialog(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final ctrl = TextEditingController(text: widget.proxy.name);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Переименовать', style: t.textStyles.headline),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: t.textStyles.body,
          decoration: InputDecoration(
            hintText: widget.proxy.displayName,
            hintStyle: t.textStyles.body.copyWith(color: c.textTertiary),
            border: InputBorder.none,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Отмена',
                style: t.textStyles.body.copyWith(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final newName = ctrl.text.trim();
              final updated = widget.proxy.copyWith(name: newName);
              final group = widget.state.mtProtoGroups
                  .where((g) => g.id == widget.group.id)
                  .cast<MtProtoProxyGroup?>()
                  .firstOrNull;
              if (group != null) {
                final idx = group.proxies.indexOf(widget.proxy);
                if (idx >= 0) {
                  group.proxies[idx] = updated;
                  widget.state.persistMtProtoGroups();
                  if (mounted) setState(() {});
                }
              }
              Navigator.of(ctx).pop();
            },
            child: Text('Сохранить',
                style: t.textStyles.body.copyWith(color: c.blue)),
          ),
        ],
      ),
    );
  }

  void _showActions(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final fav = widget.proxy.isFavorite;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        margin: EdgeInsets.fromLTRB(
            8, 0, 8, MediaQuery.of(context).padding.bottom + 8),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: c.bgSecondary,
          borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 6),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: c.textQuaternary,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(children: [
              Text(widget.proxy.displayName,
                  style: t.textStyles.headline,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
          IosListTile(
            leadingIcon: CupertinoIcons.paperplane,
            leadingIconBg: c.fill,
            title: 'Установить в Telegram',
            onTap: () {
              Navigator.of(context).pop();
              showInstallMtProtoProxySheet(context, widget.proxy);
            },
          ),
          Container(
              margin: const EdgeInsets.only(left: 54),
              height: 0.5,
              color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.info_circle,
            leadingIconBg: c.fill,
            title: 'О прокси',
            onTap: () {
              Navigator.of(context).pop();
              _showProxyInfo(context);
            },
          ),
          Container(
              margin: const EdgeInsets.only(left: 54),
              height: 0.5,
              color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.pencil,
            leadingIconBg: c.fill,
            title: 'Переименовать',
            onTap: () {
              Navigator.of(context).pop();
              _showRenameDialog(context);
            },
          ),
          Container(
              margin: const EdgeInsets.only(left: 54),
              height: 0.5,
              color: c.separator),
          IosListTile(
            leadingIcon:
                fav ? CupertinoIcons.star_slash : CupertinoIcons.star_fill,
            leadingIconBg: c.fill,
            title: fav ? 'Убрать из избранного' : 'В избранное',
            onTap: () {
              widget.state.toggleFavoriteMtProto(widget.proxy);
              Navigator.of(context).pop();
              if (mounted) setState(() {});
            },
          ),
          Container(
              margin: const EdgeInsets.only(left: 54),
              height: 0.5,
              color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.wifi,
            leadingIconBg: c.fill,
            title: 'Пингануть',
            onTap: () {
              Navigator.of(context).pop();
              _pingOne();
            },
          ),
          Container(
              margin: const EdgeInsets.only(left: 54),
              height: 0.5,
              color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.waveform_path_ecg,
            leadingIconBg: c.fill,
            title: 'Диагностика',
            onTap: () {
              Navigator.of(context).pop();
              _showDiagnostics(context);
            },
          ),
          Container(
              margin: const EdgeInsets.only(left: 54),
              height: 0.5,
              color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.share,
            leadingIconBg: c.fill,
            title: 'Поделиться группой',
            onTap: () {
              Navigator.of(context).pop();
              _showShareGroupSheet(context);
            },
          ),
          Container(
              margin: const EdgeInsets.only(left: 54),
              height: 0.5,
              color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.link,
            leadingIconBg: c.fill,
            title: 'Поделиться',
            onTap: () {
              Navigator.of(context).pop();
              _shareProxy(context);
            },
          ),
          Container(
              margin: const EdgeInsets.only(left: 54),
              height: 0.5,
              color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.trash,
            leadingIconBg: c.red,
            title: 'Удалить прокси',
            titleColor: c.red,
            onTap: () {
              widget.state.removeMtProtoProxy(widget.group.id, widget.proxy);
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 8),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ── «О прокси» ──────────────────────────────────────────────────────────
  void _showProxyInfo(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final p = widget.proxy;

    final jsonData = <String, dynamic>{
      if (p.name.isNotEmpty) 'name': p.name,
      'type': p.kind.name,
      'server': p.server,
      'port': p.port,
      if (p.kind == TelegramProxyKind.mtproto && p.secret.isNotEmpty)
        'secret': p.secret,
      if (p.kind == TelegramProxyKind.socks5 && p.user.isNotEmpty)
        'user': p.user,
      if (p.kind == TelegramProxyKind.socks5 && p.pass.isNotEmpty)
        'pass': p.pass,
      if (p.pingMs != null) 'ping_ms': p.pingMs,
    };
    const encoder = JsonEncoder.withIndent('  ');
    final jsonText = encoder.convert(jsonData);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollController) => Container(
          margin: EdgeInsets.fromLTRB(
              8, 0, 8, MediaQuery.of(context).padding.bottom + 8),
          decoration: BoxDecoration(
            color: c.bgSecondary,
            borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: c.textQuaternary,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('О прокси', style: t.textStyles.headline),
                        const SizedBox(height: 2),
                        Text(p.kind.label,
                            style: t.textStyles.footnote
                                .copyWith(color: c.textSecondary)),
                      ]),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration:
                        BoxDecoration(color: c.fill, shape: BoxShape.circle),
                    child: Icon(CupertinoIcons.xmark,
                        size: 14, color: c.textSecondary),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  _InfoSection(title: 'Основное', c: c, t: t, rows: [
                    _InfoRow('Название', _stripFlag(p.displayName), c, t),
                    _InfoRow('Тип', p.kind.label, c, t),
                    _InfoRow('Сервер', p.server, c, t),
                    _InfoRow('Порт', '${p.port}', c, t),
                    if (p.pingMs != null)
                      _InfoRow('Пинг', '${p.pingMs} ms', c, t,
                          valueColor: _pingColor(p.pingMs, c)),
                  ]),
                  const SizedBox(height: 12),
                  if (p.kind == TelegramProxyKind.mtproto &&
                      p.secret.isNotEmpty)
                    _InfoSection(title: 'MTProto', c: c, t: t, rows: [
                      _InfoRow('Secret', p.secret, c, t),
                    ]),
                  if (p.kind == TelegramProxyKind.socks5 &&
                      (p.user.isNotEmpty || p.pass.isNotEmpty))
                    _InfoSection(title: 'SOCKS5', c: c, t: t, rows: [
                      if (p.user.isNotEmpty) _InfoRow('Логин', p.user, c, t),
                      if (p.pass.isNotEmpty) _InfoRow('Пароль', p.pass, c, t),
                    ]),
                  const SizedBox(height: 12),
                  Text('Json данные',
                      style: t.textStyles.subheadline.copyWith(
                          color: c.blue, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.bgPrimary,
                      borderRadius:
                          IosShapes.continuous(IosShapes.radiusMedium),
                    ),
                    child: SelectableText(
                      jsonText,
                      style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 11.5,
                        color: c.textSecondary,
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  IosButton(
                    label: 'Копировать ссылку',
                    style: IosButtonStyle.secondary,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(
                          text: widget.proxy.buildLink(https: true)));
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Ссылка скопирована'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── «Диагностика» ───────────────────────────────────────────────────────
  // У MTProto-прокси нет нашего xray-хендшейка, поэтому полноценный
  // DiagnosticsScreen (он завязан на VpnNode) не подходит. Делаем серию
  // TCP-замеров до server:port — это показывает доступность и стабильность.
  void _showDiagnostics(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MtProtoDiagnosticsSheet(proxy: widget.proxy),
    );
  }

  // ── «Поделиться группой» ────────────────────────────────────────────────
  // Ведёт на тот же экран ShareScreen, что и у групп серверов — вкладка
  // MTProto открывается в режиме «Поделиться группой» (галочки + копирование).
  void _showShareGroupSheet(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ShareScreen(initialMtProtoGroup: widget.group),
    ));
  }

  String _flag(String name) {
    final runes = name.runes.toList();
    if (runes.isEmpty) return '🌐';
    if (runes.length >= 2 &&
        runes[0] >= 0x1F1E6 && runes[0] <= 0x1F1FF &&
        runes[1] >= 0x1F1E6 && runes[1] <= 0x1F1FF) {
      return String.fromCharCodes([runes[0], runes[1]]);
    }
    return '🌐';
  }

  String _stripFlag(String name) {
    final flag = _flag(name);
    if (name.startsWith(flag)) return name.substring(flag.length).trim();
    return name;
  }

  /// true, если в начале имени стоит настоящий emoji-флаг страны.
  bool _hasCountryFlag(String name) {
    final runes = name.runes.toList();
    return runes.length >= 2 &&
        runes[0] >= 0x1F1E6 &&
        runes[0] <= 0x1F1FF &&
        runes[1] >= 0x1F1E6 &&
        runes[1] <= 0x1F1FF;
  }

  /// Иконка MTProto-тайла: если в имени есть флаг страны — показываем его,
  /// иначе вместо заглушки-глобуса показываем логотип Telegram.
  Widget _buildProxyIcon(String displayName) {
    if (_hasCountryFlag(displayName)) {
      return Text(_flag(displayName), style: const TextStyle(fontSize: 22));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        'assets/telegram.png',
        width: 28,
        height: 28,
        fit: BoxFit.cover,
        // Если ассет не подключён — не падаем, показываем глобус как раньше.
        errorBuilder: (_, __, ___) =>
            const Text('🌐', style: TextStyle(fontSize: 22)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final pingMs = widget.proxy.pingMs;
    final displayName = widget.proxy.displayName;

    return IosCard(
      onTap: () => showInstallMtProtoProxySheet(context, widget.proxy),
      onLongPress: () => _showActions(context),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      radius: IosShapes.radiusLarge,
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: c.fill,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: _buildProxyIcon(displayName)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_stripFlag(displayName), style: t.textStyles.body, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Row(children: [
              Text(widget.proxy.kind.label,
                  style: t.textStyles.caption2.copyWith(color: c.textTertiary, letterSpacing: 0.5)),
              const SizedBox(width: 6),
              Container(width: 3, height: 3, decoration: BoxDecoration(color: c.textTertiary, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              if (pingMs != null)
                Text(
                  '$pingMs ms',
                  style: t.textStyles.caption1.copyWith(color: _pingColor(pingMs, c)),
                ),
            ]),
          ]),
        ),
        // Кнопка пинга (wifi)
        _TileButton(
          icon: CupertinoIcons.wifi,
          onTap: _pingOne,
          color: c.textTertiary,
        ),
        // Звёздочка «избранное» — теперь работает (MtProtoProxy.isFavorite)
        _TileButton(
          icon: widget.proxy.isFavorite
              ? CupertinoIcons.star_fill
              : CupertinoIcons.star,
          onTap: () {
            widget.state.toggleFavoriteMtProto(widget.proxy);
            if (mounted) setState(() {});
          },
          color: widget.proxy.isFavorite ? c.yellow : c.textTertiary,
        ),
        const SizedBox(width: 2),
        // Стрелка вправо
        _TileButton(
          icon: CupertinoIcons.chevron_right,
          onTap: () => _showActions(context),
          color: c.textTertiary,
          size: 14,
        ),
      ]),
    );
  }
}

// ── Диагностика MTProto-прокси ────────────────────────────────────────────────
//
// MTProto-прокси не поднимается xray-движком приложения (он устанавливается
// внутрь Telegram), поэтому полноценная диагностика VPN-узла к нему неприменима.
// Здесь мы делаем серию TCP-замеров до server:port: это объективно показывает
// доступность прокси, среднюю задержку и стабильность соединения.
class _MtProtoDiagnosticsSheet extends StatefulWidget {
  final MtProtoProxy proxy;
  const _MtProtoDiagnosticsSheet({required this.proxy});

  @override
  State<_MtProtoDiagnosticsSheet> createState() =>
      _MtProtoDiagnosticsSheetState();
}

class _MtProtoDiagnosticsSheetState extends State<_MtProtoDiagnosticsSheet> {
  static const int _attempts = 8;

  bool _running = false;
  bool _done = false;
  final List<int?> _results = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _done = false;
      _results.clear();
    });
    for (var i = 0; i < _attempts; i++) {
      final ms = await TcpPing.ping(widget.proxy.server, widget.proxy.port);
      if (!mounted) return;
      setState(() => _results.add(ms));
    }
    // Записываем последний удачный замер как актуальный пинг прокси.
    final lastOk = _results.lastWhere((e) => e != null, orElse: () => null);
    if (lastOk != null) widget.proxy.pingMs = lastOk;
    if (!mounted) return;
    setState(() {
      _running = false;
      _done = true;
    });
  }

  int get _okCount => _results.where((e) => e != null).length;

  int? get _avg {
    final ok = _results.whereType<int>().toList();
    if (ok.isEmpty) return null;
    return (ok.reduce((a, b) => a + b) / ok.length).round();
  }

  int? get _best {
    final ok = _results.whereType<int>().toList();
    if (ok.isEmpty) return null;
    return ok.reduce((a, b) => a < b ? a : b);
  }

  int? get _worst {
    final ok = _results.whereType<int>().toList();
    if (ok.isEmpty) return null;
    return ok.reduce((a, b) => a > b ? a : b);
  }

  Color _verdictColor(IosColors c) {
    if (_results.isEmpty) return c.textTertiary;
    final loss = _attempts - _okCount;
    if (_okCount == 0) return c.red;
    if (loss > 0 || (_avg ?? 9999) > 400) return c.orange;
    return c.green;
  }

  String _verdictText() {
    if (!_done) return 'Идёт проверка…';
    if (_okCount == 0) return 'Прокси недоступен';
    final loss = _attempts - _okCount;
    if (loss > 0) return 'Доступен, но есть потери пакетов';
    if ((_avg ?? 0) > 400) return 'Доступен, но задержка высокая';
    return 'Прокси доступен и стабилен';
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final p = widget.proxy;

    return Container(
      margin: EdgeInsets.fromLTRB(
          8, 0, 8, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: c.bgSecondary,
        borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          margin: const EdgeInsets.only(top: 8, bottom: 6),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
              color: c.textQuaternary,
              borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Диагностика', style: t.textStyles.headline),
                    const SizedBox(height: 2),
                    Text('${p.server}:${p.port}',
                        style: t.textStyles.footnote
                            .copyWith(color: c.textSecondary),
                        overflow: TextOverflow.ellipsis),
                  ]),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 28,
                height: 28,
                decoration:
                    BoxDecoration(color: c.fill, shape: BoxShape.circle),
                child: Icon(CupertinoIcons.xmark,
                    size: 14, color: c.textSecondary),
              ),
            ),
          ]),
        ),
        // Вердикт
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _verdictColor(c).withValues(alpha: 0.12),
              borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
            ),
            child: Row(children: [
              if (_running)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CupertinoActivityIndicator(),
                )
              else
                Icon(
                  _okCount == 0
                      ? CupertinoIcons.xmark_circle_fill
                      : (_attempts - _okCount > 0
                          ? CupertinoIcons.exclamationmark_triangle_fill
                          : CupertinoIcons.checkmark_circle_fill),
                  size: 18,
                  color: _verdictColor(c),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_verdictText(),
                    style: t.textStyles.subheadline
                        .copyWith(color: _verdictColor(c))),
              ),
            ]),
          ),
        ),
        // Сводка
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(children: [
            _DiagStat(
                label: 'Успешно',
                value: '$_okCount/$_attempts',
                c: c,
                t: t),
            _DiagStat(
                label: 'Средний',
                value: _avg != null ? '$_avg ms' : '—',
                c: c,
                t: t),
            _DiagStat(
                label: 'Лучший',
                value: _best != null ? '$_best ms' : '—',
                c: c,
                t: t),
            _DiagStat(
                label: 'Худший',
                value: _worst != null ? '$_worst ms' : '—',
                c: c,
                t: t),
          ]),
        ),
        // Лог замеров
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.bgPrimary,
              borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < _results.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Text('Замер ${i + 1}',
                            style: t.textStyles.footnote
                                .copyWith(color: c.textSecondary)),
                        const Spacer(),
                        Text(
                          _results[i] != null
                              ? '${_results[i]} ms'
                              : 'таймаут',
                          style: t.textStyles.footnote.copyWith(
                            color: _results[i] != null
                                ? (_results[i]! < 100
                                    ? c.green
                                    : _results[i]! < 250
                                        ? c.orange
                                        : c.red)
                                : c.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ]),
                    ),
                  if (_running)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CupertinoActivityIndicator(),
                        ),
                        const SizedBox(width: 8),
                        Text('Замер ${_results.length + 1}…',
                            style: t.textStyles.footnote
                                .copyWith(color: c.textTertiary)),
                      ]),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: IosButton(
            label: _running ? 'Проверка…' : 'Повторить',
            style: IosButtonStyle.secondary,
            leadingIcon: CupertinoIcons.arrow_clockwise,
            loading: _running,
            onPressed: _running ? null : _run,
          ),
        ),
      ]),
    );
  }
}

class _DiagStat extends StatelessWidget {
  final String label;
  final String value;
  final IosColors c;
  final IosThemeData t;
  const _DiagStat({
    required this.label,
    required this.value,
    required this.c,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: c.bgPrimary,
          borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
        ),
        child: Column(children: [
          Text(value,
              style: t.textStyles.subheadline
                  .copyWith(fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label,
              style: t.textStyles.caption2.copyWith(color: c.textTertiary)),
        ]),
      ),
    );
  }
}

// lib/screens/home_screen.dart
//
// Главный экран: статус соединения, список групп серверов и MTProto-прокси.
//
// Файл — корень библиотеки home_screen. Сам HomeScreen и его State ниже, а
// крупные виджеты (шапка, карточка статуса, тайлы сервера/прокси, заголовки
// групп, шиты) вынесены в part-файлы lib/screens/home/. Путь файла не менялся,
// поэтому `import '.../home_screen.dart'` продолжает работать без правок.

library home_screen;

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

part 'home/header.dart';
part 'home/status_card.dart';
part 'home/group_headers.dart';
part 'home/server_tile.dart';
part 'home/mtproto_tile.dart';
part 'home/info_display.dart';

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
              // cacheExtent (в пикселях) deprecated после v3.41, но новый
              // scrollCacheExtent принимает ScrollCacheExtent, а не int —
              // оставляем пиксельный вариант осознанно.
              // ignore: deprecated_member_use
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
    final messenger = ScaffoldMessenger.of(context);
    final err = await state.refreshSubscription(g);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
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

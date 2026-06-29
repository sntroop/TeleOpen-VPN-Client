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
import 'announcement/announcement_overlay.dart';
import 'announcement/broadcast_overlay.dart';
import '../models/vpn_node.dart';
import '../models/mtproto_proxy.dart';
import '../logic/telegram_proxy.dart';
import '../logic/market_api.dart';
import '../logic/launched_nodes.dart';
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
import 'package:url_launcher/url_launcher.dart';

part 'home/header.dart';
part 'home/status_card.dart';
part 'home/group_headers.dart';
part 'home/server_tile.dart';
part 'home/mtproto_tile.dart';
part 'home/info_display.dart';

/// Режимы сортировки списка серверов (выбираются в баре под кнопками).
enum ServerSort {
  none,
  pingAsc,
  pingDesc,
  nameAsc,
  nameDesc,
  dateNew,
  dateOld,
  favFirst,
  availFirst,
  protocol,
}

extension ServerSortX on ServerSort {
  String get label => switch (this) {
        ServerSort.none => 'По умолчанию',
        ServerSort.pingAsc => 'Пинг ↑ (быстрые)',
        ServerSort.pingDesc => 'Пинг ↓ (медленные)',
        ServerSort.nameAsc => 'Имя А→Я',
        ServerSort.nameDesc => 'Имя Я→А',
        ServerSort.dateNew => 'Сначала новые',
        ServerSort.dateOld => 'Сначала старые',
        ServerSort.favFirst => 'Сначала избранные',
        ServerSort.availFirst => 'Сначала доступные',
        ServerSort.protocol => 'По протоколу',
      };

  IconData get icon => switch (this) {
        ServerSort.none => CupertinoIcons.list_bullet,
        ServerSort.pingAsc => CupertinoIcons.arrow_up_circle,
        ServerSort.pingDesc => CupertinoIcons.arrow_down_circle,
        ServerSort.nameAsc => CupertinoIcons.textformat_abc,
        ServerSort.nameDesc => CupertinoIcons.textformat_abc,
        ServerSort.dateNew => CupertinoIcons.clock,
        ServerSort.dateOld => CupertinoIcons.clock,
        ServerSort.favFirst => CupertinoIcons.star_fill,
        ServerSort.availFirst => CupertinoIcons.wifi,
        ServerSort.protocol => CupertinoIcons.shield_lefthalf_fill,
      };
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _filterIndex = 0;
  ServerSort _sortMode = ServerSort.none;
  // Переопределение сортировки для отдельной группы (по её id). Если задано —
  // имеет приоритет над глобальным _sortMode. Не персистится (как и глобальная).
  final Map<String, ServerSort> _groupSort = {};

  // Кэш отсортированного/отфильтрованного списка нод по группам. Без него
  // _buildGroups пересортировывал бы O(n log n) КАЖДОЙ группы на каждый build
  // (а build триггерится тиками пинга/статов) — при десятках тысяч нод это
  // фризы. Инвалидируется по сигнатуре (см. _displayNodes).
  final Map<String, ({String sig, List<VpnNode> nodes})> _displayCache = {};

  final ScrollController _scrollCtrl = ScrollController();
  bool _showScrollTop = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    // После первого кадра — проверяем активные анонсы (in-app push) и
    // показываем модалку. Тихо выходит, если юзер не залогинен.
    //
    // ВАЖНО: JWT восстанавливается из Keystore асинхронно (см. _restoreJwt в
    // app_state_user.dart) и к первому кадру обычно ещё null. Раньше из-за
    // этого maybeShowAnnouncements молча выходила на холодном старте и анонсы
    // не доходили. Поэтому ждём готовности токена (короткий поллинг с потолком),
    // и только потом дёргаем /announcements/active.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: discarded_futures
      _showAnnouncementsWhenReady();
      // ignore: discarded_futures
      _pullAndShowBroadcasts();
    });
  }

  /// Подтягивает живую мету teleopen-подписок (бренд/renew + рассылки продавца)
  /// и показывает накопившиеся рассылки. Не зависит от Telegram-логина —
  /// рассылка привязана к подписке, а не к аккаунту.
  Future<void> _pullAndShowBroadcasts() async {
    if (!mounted) return;
    final state = AppStateScope.of(context, listen: false);
    await state.pullTeleopenMetas();
    if (!mounted) return;
    await maybeShowBroadcasts(context, state);
  }

  /// Дожидается восстановления JWT (он подтягивается из Keystore асинхронно
  /// после старта), затем один раз проверяет активные анонсы. Потолок ожидания
  /// — ~10 с, чтобы незалогиненный/без токена случай не крутился вечно.
  Future<void> _showAnnouncementsWhenReady() async {
    for (var i = 0; i < 40; i++) {
      if (!mounted) return;
      final state = AppStateScope.of(context, listen: false);
      if (state.currentUser != null && MarketApi.jwt != null) {
        await maybeShowAnnouncements(context, state);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
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
            SliverToBoxAdapter(child: _buildSortBar(context)),
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
                      child: Icon(CupertinoIcons.arrow_up,
                          color: c.blue.computeLuminance() > 0.6 ? Colors.black : Colors.white,
                          size: 20),
                    ),
                  ),
                ),
              ),
            ),
            // Плавающее облачко выбранного сервера: видно, когда уехала
            // карточка статуса с кнопкой «Подключить» и выбран сервер.
            _buildConnectCloud(context, state),
          ],
        ),
      ),
    );
  }

  /// Верхнее облачко с полным названием выбранного сервера и кнопкой
  /// «Подключить». Появляется при скролле вниз (кнопка «Подключить» в карточке
  /// статуса уже не видна), если сервер выбран и ещё не подключён.
  Widget _buildConnectCloud(BuildContext context, AppState state) {
    final t = IosTheme.of(context);
    final c = t.colors;

    final node = state.activeNode;
    final isConnected  = state.status == VpnStatus.connected;
    final isConnecting = state.status == VpnStatus.connecting;
    // В режиме обхода DPI сервер не выбирают — облачко не нужно.
    final show = _showScrollTop &&
        node != null &&
        !state.settings.bdpiModeEnabled &&
        !isConnected;

    return Positioned(
      top: 8,
      left: 12,
      right: 12,
      child: AnimatedSlide(
        offset: show ? Offset.zero : const Offset(0, -1.6),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: show ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !show,
            child: node == null
                ? const SizedBox.shrink()
                : Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    decoration: BoxDecoration(
                      color: c.bgSecondary,
                      borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
                      border: Border.all(color: c.blue.withValues(alpha: 0.4), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: c.fill,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(CupertinoIcons.location_fill, size: 18, color: c.blue),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(node.name,
                                style: t.textStyles.subheadline.copyWith(fontWeight: FontWeight.w600),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            Text('${node.protocolLabel} • ${node.address}',
                                style: t.textStyles.caption1.copyWith(color: c.textSecondary),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      IosButton(
                        label: isConnecting ? 'Подключение…' : 'Подключить',
                        style: IosButtonStyle.primary,
                        fullWidth: false,
                        loading: isConnecting,
                        onPressed: isConnecting ? null : () => state.connect(node),
                      ),
                    ]),
                  ),
          ),
        ),
      ),
    );
  }

  // ── Сортировка ─────────────────────────────────────────────────────────

  /// Возвращает НОВЫЙ отсортированный список (не мутирует g.nodes).
  /// Сортировка стабильная: при равенстве сохраняем исходный порядок (= порядок
  /// добавления), поэтому он же служит ключом «по дате добавления».
  /// Отображаемый список нод группы (фильтр + сортировка) с кэшированием.
  /// Пересчитывается только когда меняется состав/контент нод (state.nodesRevision),
  /// фильтр или режим сортировки — а не на каждый build.
  List<VpnNode> _displayNodes(AppState state, VpnGroup g) {
    final mode = _groupSort[g.id] ?? _sortMode;
    final sig = '${g.nodes.length}|${state.nodesRevision}|$_filterIndex|${mode.index}';
    final cached = _displayCache[g.id];
    if (cached != null && cached.sig == sig) return cached.nodes;

    var nodes = g.nodes;
    if (_filterIndex == 1) {
      nodes = nodes.where((n) => n.isFavorite).toList();
    }
    nodes = _applySort(nodes, mode);
    _displayCache[g.id] = (sig: sig, nodes: nodes);
    return nodes;
  }

  List<VpnNode> _applySort(List<VpnNode> nodes, ServerSort mode) {
    if (mode == ServerSort.none) return nodes;

    final indexed = [for (var i = 0; i < nodes.length; i++) (i, nodes[i])];

    // Нода без измеренного пинга считается «худшей» — всегда в конец при
    // сортировке по пингу.
    int byPing((int, VpnNode) a, (int, VpnNode) b, {required bool asc}) {
      final pa = a.$2.pingMs, pb = b.$2.pingMs;
      if (pa == null && pb == null) return a.$1.compareTo(b.$1);
      if (pa == null) return 1;
      if (pb == null) return -1;
      final r = asc ? pa.compareTo(pb) : pb.compareTo(pa);
      return r != 0 ? r : a.$1.compareTo(b.$1);
    }

    int tie(int r, (int, VpnNode) a, (int, VpnNode) b) =>
        r != 0 ? r : a.$1.compareTo(b.$1);

    indexed.sort((a, b) {
      final na = a.$2, nb = b.$2;
      return switch (mode) {
        ServerSort.pingAsc => byPing(a, b, asc: true),
        ServerSort.pingDesc => byPing(a, b, asc: false),
        ServerSort.nameAsc =>
          tie(na.name.toLowerCase().compareTo(nb.name.toLowerCase()), a, b),
        ServerSort.nameDesc =>
          tie(nb.name.toLowerCase().compareTo(na.name.toLowerCase()), a, b),
        ServerSort.dateNew => b.$1.compareTo(a.$1),
        ServerSort.dateOld => a.$1.compareTo(b.$1),
        ServerSort.favFirst => tie(
            (nb.isFavorite ? 1 : 0).compareTo(na.isFavorite ? 1 : 0), a, b),
        ServerSort.availFirst => tie(
            (nb.pingMs != null ? 1 : 0).compareTo(na.pingMs != null ? 1 : 0),
            a, b),
        ServerSort.protocol =>
          tie(na.protocolLabel.compareTo(nb.protocolLabel), a, b),
        ServerSort.none => a.$1.compareTo(b.$1),
      };
    });
    return [for (final e in indexed) e.$2];
  }

  Widget _buildSortBar(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final active = _sortMode != ServerSort.none;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _showSortSheet,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: active ? c.blue.withValues(alpha: 0.15) : c.fill,
                borderRadius: IosShapes.continuous(IosShapes.radiusButton),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(CupertinoIcons.arrow_up_arrow_down,
                    size: 15, color: active ? c.blue : c.textSecondary),
                const SizedBox(width: 6),
                Text(
                  active ? _sortMode.label : 'Сортировка',
                  style: t.textStyles.footnote.copyWith(
                    color: active ? c.blue : c.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ]),
            ),
          ),
          if (active) ...[
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _sortMode = ServerSort.none),
              child: Icon(CupertinoIcons.clear_circled_solid,
                  size: 18, color: c.textTertiary),
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }

  void _showSortSheet({String? groupId}) {
    final t = IosTheme.of(context);
    final c = t.colors;
    // Для группы текущий выбор — её переопределение (или «По умолчанию»),
    // для общей — глобальный режим.
    final current =
        groupId != null ? (_groupSort[groupId] ?? ServerSort.none) : _sortMode;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        margin: EdgeInsets.fromLTRB(8, 0, 8, MediaQuery.of(context).padding.bottom + 8),
        decoration: BoxDecoration(
          color: c.bgSecondary,
          borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 6),
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: c.textQuaternary, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(children: [
                  Text(groupId == null ? 'Сортировка' : 'Сортировка группы',
                      style: t.textStyles.headline),
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(CupertinoIcons.xmark_circle_fill,
                        size: 28, color: c.textQuaternary),
                  ),
                ]),
              ),
              for (final m in ServerSort.values)
                IosListTile(
                  leadingIcon: m.icon,
                  leadingIconBg: c.fill,
                  title: m.label,
                  trailing: m == current
                      ? Icon(CupertinoIcons.check_mark, size: 18, color: c.blue)
                      : null,
                  onTap: () {
                    setState(() {
                      if (groupId == null) {
                        _sortMode = m;
                      } else if (m == ServerSort.none) {
                        // «По умолчанию» для группы = убрать переопределение
                        // (вернуться к общей сортировке).
                        _groupSort.remove(groupId);
                      } else {
                        _groupSort[groupId] = m;
                      }
                    });
                    Navigator.of(context).pop();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
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
      final nodes = _displayNodes(state, g);
      if (nodes.isEmpty && _filterIndex == 1) continue;

      widgets.add(SliverToBoxAdapter(
        child: _GroupHeader(
          group: g,
          onRefresh: (g.sourceUrl != null || g.id.startsWith('market_'))
              ? () => _refreshGroup(context, state, g)
              : null,
          onDelete: () => _confirmDeleteGroup(context, state, g),
          onToggleCollapse: () => setState(() => g.isCollapsed = !g.isCollapsed),
          onSort: () => _showSortSheet(groupId: g.id),
          sortActive: _groupSort[g.id] != null &&
              _groupSort[g.id] != ServerSort.none,
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

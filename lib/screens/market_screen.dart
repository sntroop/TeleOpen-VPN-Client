// lib/screens/market_screen.dart
//
// Главный экран маркетплейса: список подписок с поиском и фильтром по тегам.

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ios_theme.dart';
import '../main.dart';
import '../models/market.dart';
import '../logic/market_api.dart';
import 'market_detail_screen.dart';
import 'login_screen.dart';
import 'author_panel_screen.dart';
import 'admin_panel_screen.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  List<MarketItem> _items = [];
  final Set<String> _selectedTags = {};
  bool _loading = true;
  String? _error;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await MarketApi.list(
        search: _searchCtrl.text.trim(),
        tags: _selectedTags.toList(),
        limit: 50,
      );
      if (!mounted) return;
      setState(() {
        // Бэкенд уже отдаёт список в порядке убывания score (топ). Нам нужно
        // лишь поднять подписки с бейджем TeleOpen наверх, СОХРАНИВ при этом
        // порядок по score внутри каждой группы. List.sort в Dart нестабильна,
        // поэтому добавляем индекс как вторичный ключ — иначе score-порядок
        // перемешивается случайно на каждой загрузке.
        final indexed = res.items.asMap().entries.toList()
          ..sort((a, b) {
            final aBadge = a.value.teleOpenBadge != null ? 0 : 1;
            final bBadge = b.value.teleOpenBadge != null ? 0 : 1;
            if (aBadge != bBadge) return aBadge.compareTo(bBadge);
            return a.key
                .compareTo(b.key); // тай-брейк = исходный порядок (score)
          });
        _items = indexed.map((e) => e.value).toList();
        _total = res.total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _toggleTag(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
    });
    _load();
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
        child: Column(children: [
          // ── Header ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
            child: Row(children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(children: [
                    Icon(CupertinoIcons.chevron_back,
                        size: 22, color: c.textPrimary),
                    Text(' Назад',
                        style:
                            t.textStyles.body.copyWith(color: c.textPrimary)),
                  ]),
                ),
              ),
              const Spacer(),
              // Кнопка модератора (только для админа)
              if (state.currentUser?.isAdmin == true)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AdminPanelScreen(),
                  )),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: c.fill,
                        borderRadius:
                            BorderRadius.circular(IosShapes.radiusPill),
                      ),
                      child: Row(children: [
                        Icon(CupertinoIcons.shield_fill,
                            size: 14, color: c.textPrimary),
                        const SizedBox(width: 4),
                        Text('Модерация', style: t.textStyles.subheadline),
                      ]),
                    ),
                  ),
                ),
              // Аккаунт / войти
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  if (state.currentUser == null) {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const LoginScreen(),
                    ));
                  } else {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AuthorPanelScreen(),
                    ));
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.fill,
                    borderRadius: BorderRadius.circular(IosShapes.radiusPill),
                  ),
                  child: Row(children: [
                    Icon(
                      state.currentUser == null
                          ? CupertinoIcons.paperplane
                          : CupertinoIcons.person_fill,
                      size: 14,
                      color: c.textPrimary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      state.currentUser?.displayName ?? 'Войти',
                      style: t.textStyles.subheadline,
                    ),
                  ]),
                ),
              ),
            ]),
          ),

          // ── Title ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(children: [
              Text('Маркетплейс', style: t.textStyles.largeTitle),
            ]),
          ),

          // ── Search ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: c.fill,
                borderRadius: IosShapes.continuous(IosShapes.radiusField),
              ),
              child: Row(children: [
                Icon(CupertinoIcons.search, size: 18, color: c.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    cursorColor: c.textPrimary,
                    style: t.textStyles.body,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Поиск подписок…',
                      hintStyle:
                          t.textStyles.body.copyWith(color: c.textTertiary),
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ),
                if (_searchCtrl.text.isNotEmpty)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _searchCtrl.clear();
                    },
                    child: Icon(CupertinoIcons.xmark_circle_fill,
                        size: 18, color: c.textTertiary),
                  ),
              ]),
            ),
          ),

          // ── Tags chips ────────────────────────────────────────────────
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              physics: const BouncingScrollPhysics(),
              itemCount: kMarketValidTags.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final tag = kMarketValidTags[i];
                final selected = _selectedTags.contains(tag);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggleTag(tag),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? c.textPrimary : c.fill,
                      borderRadius: BorderRadius.circular(IosShapes.radiusPill),
                    ),
                    child: Center(
                      child: Text(
                        tag,
                        style: t.textStyles.footnote.copyWith(
                          color: selected ? c.bgSecondary : c.textPrimary,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Count + reset filters
          if (_selectedTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(children: [
                Text(
                  '$_total ${_pluralize(_total)}',
                  style: t.textStyles.footnote.copyWith(color: c.textSecondary),
                ),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => _selectedTags.clear());
                    _load();
                  },
                  child: Text('Сбросить',
                      style: t.textStyles.footnote.copyWith(color: c.red)),
                ),
              ]),
            ),

          // ── List ──────────────────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              color: c.textPrimary,
              backgroundColor: c.bgSecondary,
              onRefresh: _load,
              child: _loading
                  ? Center(
                      child: CupertinoActivityIndicator(color: c.textPrimary))
                  : _error != null
                      ? _ErrorView(message: _error!, onRetry: _load)
                      : _items.isEmpty
                          ? _EmptyView()
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              physics: const BouncingScrollPhysics(
                                  parent: AlwaysScrollableScrollPhysics()),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) => _MarketCard(
                                item: _items[i],
                                onTap: () async {
                                  await Navigator.of(context)
                                      .push(MaterialPageRoute(
                                    builder: (_) => MarketDetailScreen(
                                        groupId: _items[i].id),
                                  ));
                                  _load();
                                },
                              ),
                            ),
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 4),
        ]),
      ),
    );
  }

  String _pluralize(int n) {
    final last = n % 10;
    final lastTwo = n % 100;
    if (lastTwo >= 11 && lastTwo <= 14) return 'подписок';
    if (last == 1) return 'подписка';
    if (last >= 2 && last <= 4) return 'подписки';
    return 'подписок';
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Карточка одной подписки в списке
// ══════════════════════════════════════════════════════════════════════════

class _MarketCard extends StatelessWidget {
  final MarketItem item;
  final VoidCallback onTap;
  const _MarketCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return IosCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      radius: IosShapes.radiusLarge,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Иконка + контакт автора
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CardIcon(url: item.iconUrl, name: item.name),
            if (_normalizeContactUri(item.contactUrl) != null) ...[
              const SizedBox(height: 8),
              _MarketContactButton(url: item.contactUrl),
            ],
          ],
        ),
        const SizedBox(width: 12),

        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(item.name,
                    style: t.textStyles.headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 6),
              if (item.ratingCount > 0) ...[
                Icon(CupertinoIcons.star_fill, size: 13, color: c.yellow),
                const SizedBox(width: 3),
                Text(item.ratingAvg.toStringAsFixed(1),
                    style: t.textStyles.footnote
                        .copyWith(fontWeight: FontWeight.w600)),
              ] else
                Text('— ',
                    style:
                        t.textStyles.footnote.copyWith(color: c.textTertiary)),
            ]),

            // TeleOpen badge
            if (item.teleOpenBadge != null) ...[
              const SizedBox(height: 5),
              _TeleOpenBadgeChip(badge: item.teleOpenBadge!),
            ],

            const SizedBox(height: 2),

            // Автор
            Row(children: [
              Text('от ${item.author.displayName}',
                  style: t.textStyles.footnote.copyWith(color: c.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ]),

            const SizedBox(height: 8),

            // Description (1 строка)
            if (item.description.isNotEmpty)
              Text(item.description,
                  style: t.textStyles.footnote.copyWith(color: c.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),

            const SizedBox(height: 10),

            // Bottom row: серверы / онлайн / получений
            Row(children: [
              _Stat(
                  icon: CupertinoIcons.cloud_fill, value: '${item.nodesCount}'),
              const SizedBox(width: 12),
              _Stat(
                icon: CupertinoIcons.person_2_fill,
                value: '${item.activeSessions}',
                color: item.activeSessions > 0 ? c.green : null,
              ),
              const SizedBox(width: 12),
              _Stat(
                  icon: CupertinoIcons.arrow_down_circle,
                  value: _kFormat(item.getsCount)),
              const Spacer(),
              // Платная подписка выделяется ценником: самая низкая цена тарифа.
              if (item.isPaid && item.minPriceRub != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.green.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(IosShapes.radiusPill),
                  ),
                  child: Text(
                    item.tariffs.length > 1
                        ? 'от ${_rubFmt(item.minPriceRub!)} ₽'
                        : '${_rubFmt(item.minPriceRub!)} ₽',
                    style: t.textStyles.caption2
                        .copyWith(color: c.green, fontWeight: FontWeight.w700),
                  ),
                )
              else if (item.tags.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.fill,
                    borderRadius: BorderRadius.circular(IosShapes.radiusPill),
                  ),
                  child: Text(item.tags.first,
                      style: t.textStyles.caption2
                          .copyWith(color: c.textSecondary)),
                ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

Uri? _normalizeContactUri(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('@')) {
    s = 'https://t.me/${s.substring(1)}';
  } else if (s.startsWith('t.me/')) {
    s = 'https://$s';
  } else if (!s.startsWith('http://') && !s.startsWith('https://')) {
    s = 'https://t.me/$s';
  }
  final uri = Uri.tryParse(s);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  return uri;
}

class _MarketContactButton extends StatelessWidget {
  final String url;
  const _MarketContactButton({required this.url});

  Future<void> _open() async {
    final uri = _normalizeContactUri(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _open,
      child: Container(
        constraints: const BoxConstraints(minWidth: 62),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: c.blue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(IosShapes.radiusPill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(CupertinoIcons.paperplane_fill, size: 11, color: c.blue),
          const SizedBox(width: 4),
          Text(
            'Contact',
            style: t.textStyles.caption2
                .copyWith(color: c.blue, fontWeight: FontWeight.w700),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Чип TeleOpen-бейджа
// ══════════════════════════════════════════════════════════════════════════

class _TeleOpenBadgeChip extends StatelessWidget {
  final TeleOpenBadge badge;
  const _TeleOpenBadgeChip({required this.badge});

  Color _bgColor(TeleOpenBadge b, IosColors c) {
    switch (b) {
      case TeleOpenBadge.official:
        return const Color(0xFF007AFF).withValues(alpha: 0.13);
      case TeleOpenBadge.verified:
        return const Color(0xFF34C759).withValues(alpha: 0.13);
      case TeleOpenBadge.partner:
        return const Color(0xFFFF9F0A).withValues(alpha: 0.13);
    }
  }

  Color _fgColor(TeleOpenBadge b) {
    switch (b) {
      case TeleOpenBadge.official:
        return const Color(0xFF007AFF);
      case TeleOpenBadge.verified:
        return const Color(0xFF34C759);
      case TeleOpenBadge.partner:
        return const Color(0xFFFF9F0A);
    }
  }

  IconData _icon(TeleOpenBadge b) {
    switch (b) {
      case TeleOpenBadge.official:
        return CupertinoIcons.star_circle_fill;
      case TeleOpenBadge.verified:
        return CupertinoIcons.checkmark_seal_fill;
      case TeleOpenBadge.partner:
        return CupertinoIcons.hand_thumbsup_fill;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final fg = _fgColor(badge);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _bgColor(badge, c),
        borderRadius: BorderRadius.circular(IosShapes.radiusPill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_icon(badge), size: 11, color: fg),
        const SizedBox(width: 4),
        Text(
          badge.label,
          style: t.textStyles.caption2
              .copyWith(color: fg, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

class _CardIcon extends StatelessWidget {
  final String url;
  final String name;
  const _CardIcon({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    if (url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(c, name, t),
        ),
      );
    }
    return _fallback(c, name, t);
  }

  Widget _fallback(IosColors c, String name, IosThemeData t) {
    final initial = name.isEmpty ? '?'.codeUnitAt(0) : name.runes.first;
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: c.fill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          String.fromCharCode(initial).toUpperCase(),
          style: t.textStyles.title2.copyWith(color: c.textPrimary),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color? color;
  const _Stat({required this.icon, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return Row(children: [
      Icon(icon, size: 12, color: color ?? c.textTertiary),
      const SizedBox(width: 4),
      Text(value,
          style:
              t.textStyles.caption1.copyWith(color: color ?? c.textSecondary)),
    ]);
  }
}

String _kFormat(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

/// «199» или «199.50» — без копеек, когда они нулевые.
String _rubFmt(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

// ══════════════════════════════════════════════════════════════════════════

class _EmptyView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Center(
          child: Column(children: [
            Icon(CupertinoIcons.cube_box, size: 48, color: c.textTertiary),
            const SizedBox(height: 12),
            Text('Ничего не найдено',
                style: t.textStyles.body.copyWith(color: c.textSecondary)),
            const SizedBox(height: 4),
            Text('Попробуйте изменить поиск или сбросить теги',
                style: t.textStyles.footnote.copyWith(color: c.textTertiary)),
          ]),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 60),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Icon(CupertinoIcons.exclamationmark_triangle_fill,
                size: 40, color: c.red),
            const SizedBox(height: 12),
            Text('Не удалось загрузить', style: t.textStyles.body),
            const SizedBox(height: 4),
            Text(message,
                style: t.textStyles.footnote.copyWith(color: c.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            IosButton(
              label: 'Повторить',
              style: IosButtonStyle.secondary,
              leadingIcon: CupertinoIcons.refresh,
              onPressed: onRetry,
              fullWidth: false,
            ),
          ]),
        ),
      ],
    );
  }
}

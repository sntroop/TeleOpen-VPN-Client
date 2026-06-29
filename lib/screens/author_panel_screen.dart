// lib/screens/author_panel_screen.dart
//
// Панель автора: мои публикации, последние отзывы, удаление, кнопка «Опубликовать».

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ios_theme.dart';
import '../main.dart';
import '../models/market.dart';
import '../logic/market_api.dart';
import 'publish_screen.dart';
import 'market_detail_screen.dart';
import 'author/edit_subscription_screen.dart';
import 'author/subscription_stats_screen.dart';

class AuthorPanelScreen extends StatefulWidget {
  const AuthorPanelScreen({super.key});

  @override
  State<AuthorPanelScreen> createState() => _AuthorPanelScreenState();
}

class _AuthorPanelScreenState extends State<AuthorPanelScreen> {
  List<MarketItemForAuthor> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = AppStateScope.of(context, listen: false).currentUser;
    if (user == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final items = await MarketApi.authorPanel(user.id);
      if (!mounted) return;
      setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _delete(MarketItemForAuthor item) async {
    final user = AppStateScope.of(context, listen: false).currentUser;
    if (user == null) return;

    final confirmed = await IosDialog.show<bool>(
      context,
      IosDialog(
        title: 'Удалить публикацию?',
        description: '«${item.name}» будет удалена навсегда.',
        actions: [
          IosButton(
            label: 'Удалить',
            style: IosButtonStyle.destructive,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          IosButton(
            label: 'Отмена',
            style: IosButtonStyle.secondary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await MarketApi.deleteGroup(groupId: item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Публикация удалена'),
        duration: Duration(seconds: 2),
      ));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ошибка: $e'),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final user = AppStateScope.of(context).currentUser;

    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
            child: Row(children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(children: [
                    Icon(CupertinoIcons.chevron_back, size: 22, color: c.textPrimary),
                    Text(' Назад', style: t.textStyles.body.copyWith(color: c.textPrimary)),
                  ]),
                ),
              ),
              const Spacer(),
              // Кнопка выйти
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  AppStateScope.of(context, listen: false).logout();
                  Navigator.of(context).pop();
                },
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('Выйти', style: t.textStyles.body.copyWith(color: c.red)),
                ),
              ),
            ]),
          ),

          // Контакты проекта — видны всегда, до карточки автора.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: IosCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                _ContactRow(
                  icon: CupertinoIcons.paperplane_fill,
                  iconBg: c.blue,
                  title: 'Связаться с разработчиком',
                  subtitle: '@sntroop',
                  url: 'https://t.me/sntroop',
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 58),
                  child: Container(height: 0.5, color: c.separator),
                ),
                _ContactRow(
                  icon: CupertinoIcons.bubble_left_bubble_right_fill,
                  iconBg: c.purple,
                  title: 'Канал сообщества',
                  subtitle: '@TLOPSpace',
                  url: 'https://t.me/TLOPSpace',
                ),
              ]),
            ),
          ),

          // User card
          if (user != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: IosCard(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: c.fill, shape: BoxShape.circle),
                    clipBehavior: Clip.antiAlias,
                    child: user.photoUrl.isNotEmpty
                      ? Image.network(user.photoUrl, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(CupertinoIcons.person_fill, size: 22, color: c.textSecondary))
                      : Icon(CupertinoIcons.person_fill, size: 22, color: c.textSecondary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(user.displayName, style: t.textStyles.headline),
                    if (user.username.isNotEmpty)
                      Text('@${user.username}', style: t.textStyles.subheadline.copyWith(color: c.textSecondary)),
                  ])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: c.fill,
                      borderRadius: BorderRadius.circular(IosShapes.radiusPill),
                    ),
                    child: Text(
                      '${_items.length} / 10',
                      style: t.textStyles.footnote.copyWith(color: c.textSecondary),
                    ),
                  ),
                ]),
              ),
            ),

          // Content
          Expanded(
            child: _loading
              ? Center(child: CupertinoActivityIndicator(color: c.textPrimary))
              : _error != null
                ? _ErrorBlock(message: _error!, onRetry: _load)
                : _items.isEmpty
                  ? _EmptyBlock()
                  : RefreshIndicator(
                      color: c.textPrimary,
                      backgroundColor: c.bgSecondary,
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _AuthorCard(
                          item: _items[i],
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => MarketDetailScreen(groupId: _items[i].id),
                          )),
                          onEdit: () async {
                            final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
                              builder: (_) => EditSubscriptionScreen(
                                groupId: _items[i].id, initialName: _items[i].name),
                            ));
                            if (changed == true) _load();
                          },
                          onStats: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => SubscriptionStatsScreen(
                              groupId: _items[i].id, title: _items[i].name),
                          )),
                          onDelete: () => _delete(_items[i]),
                        ),
                      ),
                    ),
          ),

          // Bottom: Опубликовать
          Container(
            padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 12),
            decoration: BoxDecoration(
              color: c.bgPrimary,
              border: Border(top: BorderSide(color: c.separator, width: 0.5)),
            ),
            child: IosButton(
              label: 'Опубликовать подписку',
              style: IosButtonStyle.primary,
              leadingIcon: CupertinoIcons.arrow_up_circle_fill,
              onPressed: _items.length >= 10 ? null : () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const PublishScreen(),
                ));
                _load();
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════

class _AuthorCard extends StatelessWidget {
  final MarketItemForAuthor item;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onStats;
  final VoidCallback onDelete;
  const _AuthorCard({
    required this.item,
    required this.onTap,
    required this.onEdit,
    required this.onStats,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return IosCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      radius: IosShapes.radiusLarge,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Иконка
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: item.iconUrl.isNotEmpty
              ? Image.network(item.iconUrl, width: 42, height: 42, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _fallback(c, item.name, t))
              : _fallback(c, item.name, t),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.name, style: t.textStyles.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
            Row(children: [
              Icon(CupertinoIcons.cloud_fill, size: 12, color: c.textTertiary),
              const SizedBox(width: 4),
              Text('${item.nodesCount}', style: t.textStyles.caption1.copyWith(color: c.textSecondary)),
              const SizedBox(width: 10),
              Icon(CupertinoIcons.arrow_down_circle, size: 12, color: c.textTertiary),
              const SizedBox(width: 4),
              Text('${item.getsCount}', style: t.textStyles.caption1.copyWith(color: c.textSecondary)),
              const SizedBox(width: 10),
              if (item.ratingCount > 0) ...[
                Icon(CupertinoIcons.star_fill, size: 12, color: c.yellow),
                const SizedBox(width: 4),
                Text(item.ratingAvg.toStringAsFixed(1),
                  style: t.textStyles.caption1.copyWith(color: c.textSecondary)),
              ],
            ]),
          ])),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onStats,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(CupertinoIcons.chart_bar_alt_fill, size: 19, color: c.blue),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(CupertinoIcons.pencil, size: 19, color: c.textSecondary),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDelete,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(CupertinoIcons.trash, size: 18, color: c.red),
            ),
          ),
        ]),

        // Последние отзывы
        if (item.recentReviews.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(height: 0.5, color: c.separator),
          const SizedBox(height: 10),
          Text('Последние отзывы',
            style: t.textStyles.footnote.copyWith(color: c.textTertiary, letterSpacing: 0.3)),
          const SizedBox(height: 6),
          ...item.recentReviews.take(3).map((rv) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Звёзды
              ...List.generate(5, (i) => Icon(
                i < rv.rating ? CupertinoIcons.star_fill : CupertinoIcons.star,
                size: 11, color: c.yellow,
              )),
              const SizedBox(width: 6),
              Expanded(child: rv.comment.isNotEmpty
                ? Text(rv.comment,
                    style: t.textStyles.footnote.copyWith(color: c.textSecondary),
                    maxLines: 2, overflow: TextOverflow.ellipsis)
                : Text('Без комментария',
                    style: t.textStyles.footnote.copyWith(color: c.textTertiary)),
              ),
              const SizedBox(width: 6),
              Text(rv.author.displayName,
                style: t.textStyles.caption2.copyWith(color: c.textTertiary)),
            ]),
          )),
        ],
      ]),
    );
  }

  Widget _fallback(IosColors c, String name, IosThemeData t) {
    final initial = name.isEmpty ? 63 : name.runes.first;
    return Container(
      width: 42, height: 42,
      decoration: BoxDecoration(color: c.fill, borderRadius: BorderRadius.circular(10)),
      child: Center(child: Text(
        String.fromCharCode(initial).toUpperCase(),
        style: t.textStyles.title3.copyWith(color: c.textPrimary),
      )),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String title;
  final String subtitle;
  final String url;
  const _ContactRow({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(7)),
            child: Icon(icon, size: 17, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.textStyles.body),
            Text(subtitle, style: t.textStyles.footnote.copyWith(color: c.textSecondary)),
          ])),
          Icon(CupertinoIcons.chevron_right, size: 16, color: c.textTertiary),
        ]),
      ),
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(CupertinoIcons.cube_box, size: 56, color: c.textTertiary),
        const SizedBox(height: 16),
        Text('Ты ещё ничего не публиковал', style: t.textStyles.body.copyWith(color: c.textSecondary)),
        const SizedBox(height: 6),
        Text('Нажми «Опубликовать подписку» снизу,\nчтобы поделиться своими серверами',
          style: t.textStyles.footnote.copyWith(color: c.textTertiary),
          textAlign: TextAlign.center),
      ]),
    ));
  }
}

class _ErrorBlock extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBlock({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 40, color: c.red),
        const SizedBox(height: 12),
        Text(message, style: t.textStyles.footnote.copyWith(color: c.textSecondary),
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
    ));
  }
}

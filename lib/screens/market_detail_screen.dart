// lib/screens/market_detail_screen.dart
//
// Детальная страница подписки: описание, отзывы, рейтинг звёздами,
// live-статистика, кнопка «Добавить себе» (загружает узлы и сохраняет в группы),
// возможность оставить/изменить отзыв (требует авторизации).

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ios_theme.dart';
import '../main.dart';
import '../models/market.dart';
import '../models/vpn_node.dart';
import '../logic/market_api.dart';
import '../logic/parsers.dart';
import 'login_screen.dart';

class MarketDetailScreen extends StatefulWidget {
  final int groupId;
  const MarketDetailScreen({super.key, required this.groupId});

  @override
  State<MarketDetailScreen> createState() => _MarketDetailScreenState();
}

class _MarketDetailScreenState extends State<MarketDetailScreen> {
  MarketDetail? _detail;
  LiveStats? _live;
  bool _loading = true;
  String? _error;
  bool _adding = false;

  Timer? _liveTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final userId = AppStateScope.of(context, listen: false).currentUser?.id;
      final d = await MarketApi.detail(widget.groupId, userId: userId);
      if (!mounted) return;
      setState(() { _detail = d; _loading = false; });
      _startLivePolling();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _startLivePolling() {
    _liveTimer?.cancel();
    _refreshLive();
    _liveTimer = Timer.periodic(const Duration(seconds: 12), (_) => _refreshLive());
  }

  Future<void> _refreshLive() async {
    try {
      final l = await MarketApi.liveStats(widget.groupId);
      if (!mounted) return;
      setState(() => _live = l);
    } catch (_) {
      // Тихо: это поллинг живой статистики каждые 12с, сетевой сбой здесь
      // штатен и не должен ни спамить лог, ни дёргать UI ошибкой.
    }
  }

  Future<void> _addToMy() async {
    if (_adding || _detail == null) return;

    // Ноды содержат VPN-креды — бэкенд отдаёт их только по валидному JWT.
    // Если не залогинен, ведём на вход, иначе словим сырой API[401].
    final state0 = AppStateScope.of(context, listen: false);
    if (state0.currentUser == null) {
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ));
      if (ok != true || state0.currentUser == null) return;
    }
    if (!mounted) return;

    setState(() => _adding = true);
    try {
      final res = await MarketApi.get(widget.groupId);
      if (!mounted) return;

      // Превращаем URI в VpnNode и добавляем как новую группу
      final nodes = <VpnNode>[];
      for (final mn in res.nodes) {
        final n = parseUri(mn.uri);
        if (n != null) nodes.add(n);
      }
      if (nodes.isEmpty) {
        throw Exception('Не удалось распарсить серверы');
      }

      final state = AppStateScope.of(context, listen: false);
      state.addMarketGroup(
        marketId: widget.groupId,
        title: res.name,
        nodes: nodes,
      );

      // Сообщаем бэку про начало сессии (если залогинен)
      final uid = state.currentUser?.id;
      if (uid != null) {
        // Некритичная серверная аналитика (счётчик сессий) — её сбой не должен
        // влиять на добавление подписки, поэтому намеренно глушим без лога.
        try { await MarketApi.startSession(groupId: widget.groupId); } catch (_) {}
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('«${res.name}» добавлена в твои подписки'),
        duration: const Duration(seconds: 2),
      ));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ошибка: $e'),
        duration: const Duration(seconds: 3),
      ));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _openReviewSheet() async {
    final state = AppStateScope.of(context, listen: false);
    final user = state.currentUser;
    if (user == null) {
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ));
      if (ok != true || state.currentUser == null) return;
    }
    if (!mounted) return;
    final my = _detail?.myReview;
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ReviewSheet(
        initialRating: my?.rating ?? 5,
        initialComment: my?.comment ?? '',
        onSubmit: (rating, comment) async {
          await MarketApi.postReview(
            groupId: widget.groupId,
            rating: rating,
            comment: comment,
          );
        },
      ),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: SafeArea(
        bottom: false,
        child: _loading
          ? Center(child: CupertinoActivityIndicator(color: c.textPrimary))
          : _error != null
            ? _ErrorBlock(message: _error!, onRetry: _load)
            : _buildContent(t, c),
      ),
    );
  }

  Widget _buildContent(IosThemeData t, IosColors c) {
    final d = _detail!;
    return Column(children: [
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
        ]),
      ),

      Expanded(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Top section ────────────────────────────────────────────
            SliverToBoxAdapter(child: _Hero(detail: d)),

            // ── Stats row ──────────────────────────────────────────────
            SliverToBoxAdapter(child: _StatsRow(detail: d, live: _live)),

            // ── Tags ───────────────────────────────────────────────────
            if (d.tags.isNotEmpty)
              SliverToBoxAdapter(child: _TagsRow(tags: d.tags)),

            // ── Description ────────────────────────────────────────────
            if (d.description.isNotEmpty)
              SliverToBoxAdapter(child: _DescriptionBlock(text: d.description)),

            // ── Reviews ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Row(children: [
                  Text('Отзывы', style: t.textStyles.title3),
                  const SizedBox(width: 6),
                  Text('· ${d.ratingCount}',
                    style: t.textStyles.title3.copyWith(color: c.textTertiary)),
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _openReviewSheet,
                    child: Row(children: [
                      Icon(
                        d.myReview != null ? CupertinoIcons.pencil : CupertinoIcons.plus_circle,
                        size: 16, color: c.textPrimary,
                      ),
                      const SizedBox(width: 4),
                      Text(d.myReview != null ? 'Изменить' : 'Написать',
                        style: t.textStyles.subheadline.copyWith(fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ]),
              ),
            ),
            if (d.reviews.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Text('Пока нет отзывов. Будь первым!',
                    style: t.textStyles.footnote.copyWith(color: c.textTertiary)),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                sliver: SliverList.separated(
                  itemCount: d.reviews.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _ReviewTile(review: d.reviews[i]),
                ),
              ),

            SliverToBoxAdapter(
              child: SizedBox(height: MediaQuery.of(context).padding.bottom + 100),
            ),
          ],
        ),
      ),

      // ── Bottom CTA ─────────────────────────────────────────────────
      Container(
        padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 12),
        decoration: BoxDecoration(
          color: c.bgPrimary,
          border: Border(top: BorderSide(color: c.separator, width: 0.5)),
        ),
        child: IosButton(
          label: 'Добавить в мои подписки',
          style: IosButtonStyle.primary,
          leadingIcon: CupertinoIcons.cloud_download_fill,
          loading: _adding,
          onPressed: _adding ? null : _addToMy,
        ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Hero (иконка, название, автор, рейтинг)
// ══════════════════════════════════════════════════════════════════════════

class _Hero extends StatelessWidget {
  final MarketDetail detail;
  const _Hero({required this.detail});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    Widget icon;
    if (detail.iconUrl.isNotEmpty) {
      icon = ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.network(
          detail.iconUrl,
          width: 84, height: 84, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackIcon(c, detail.name, t),
        ),
      );
    } else {
      icon = _fallbackIcon(c, detail.name, t);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        icon,
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(detail.name, style: t.textStyles.title2, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(children: [
            Icon(CupertinoIcons.person_fill, size: 12, color: c.textSecondary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(detail.author.displayName,
                style: t.textStyles.subheadline.copyWith(color: c.textSecondary),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: 8),
          if (detail.ratingCount > 0)
            Row(children: [
              ...List.generate(5, (i) {
                final filled = i < detail.ratingAvg.round();
                return Icon(
                  filled ? CupertinoIcons.star_fill : CupertinoIcons.star,
                  size: 14, color: c.yellow,
                );
              }),
              const SizedBox(width: 6),
              Text('${detail.ratingAvg.toStringAsFixed(1)} · ${detail.ratingCount}',
                style: t.textStyles.footnote.copyWith(color: c.textSecondary)),
            ])
          else
            Text('Нет оценок', style: t.textStyles.footnote.copyWith(color: c.textTertiary)),
        ])),
      ]),
    );
  }

  Widget _fallbackIcon(IosColors c, String name, IosThemeData t) {
    final initial = name.isEmpty ? '?'.codeUnitAt(0) : name.runes.first;
    return Container(
      width: 84, height: 84,
      decoration: BoxDecoration(color: c.fill, borderRadius: BorderRadius.circular(18)),
      child: Center(child: Text(
        String.fromCharCode(initial).toUpperCase(),
        style: t.textStyles.largeTitle.copyWith(color: c.textPrimary),
      )),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Stats row
// ══════════════════════════════════════════════════════════════════════════

class _StatsRow extends StatelessWidget {
  final MarketDetail detail;
  final LiveStats? live;
  const _StatsRow({required this.detail, required this.live});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    Widget cell(IconData icon, String label, String value, {Color? color}) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(children: [
          Icon(icon, size: 18, color: color ?? c.textPrimary),
          const SizedBox(height: 6),
          Text(value, style: t.textStyles.headline.copyWith(color: color ?? c.textPrimary)),
          Text(label, style: t.textStyles.caption1.copyWith(color: c.textTertiary)),
        ]),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: IosCard(
        radius: IosShapes.radiusLarge,
        padding: EdgeInsets.zero,
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          cell(CupertinoIcons.cloud_fill, 'серверов', '${detail.nodesCount}'),
          Container(width: 0.5, height: 50, color: c.separator),
          cell(
            CupertinoIcons.person_2_fill,
            'онлайн',
            '${live?.activeUsers15m ?? detail.speed15m.activeUsers}',
            color: (live?.activeUsers15m ?? 0) > 0 ? c.green : null,
          ),
          Container(width: 0.5, height: 50, color: c.separator),
          cell(CupertinoIcons.arrow_down_circle_fill, 'получений', _kFormat(detail.getsCount)),
        ]),
      ),
    );
  }
}

String _kFormat(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

// ══════════════════════════════════════════════════════════════════════════
// Tags / description / reviews
// ══════════════════════════════════════════════════════════════════════════

class _TagsRow extends StatelessWidget {
  final List<String> tags;
  const _TagsRow({required this.tags});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(spacing: 6, runSpacing: 6, children: tags.map((tag) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: c.fill,
            borderRadius: BorderRadius.circular(IosShapes.radiusPill),
          ),
          child: Text(tag, style: t.textStyles.caption1.copyWith(color: c.textSecondary)),
        );
      }).toList()),
    );
  }
}

class _DescriptionBlock extends StatefulWidget {
  final String text;
  const _DescriptionBlock({required this.text});

  @override
  State<_DescriptionBlock> createState() => _DescriptionBlockState();
}

class _DescriptionBlockState extends State<_DescriptionBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final isLong = widget.text.length > 200;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Описание', style: t.textStyles.title3),
        const SizedBox(height: 8),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: Text(
            widget.text,
            style: t.textStyles.body.copyWith(color: c.textSecondary),
            maxLines: _expanded || !isLong ? null : 4,
            overflow: _expanded || !isLong ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
        ),
        if (isLong) ...[
          const SizedBox(height: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded ? 'Свернуть' : 'Показать ещё',
              style: t.textStyles.footnote.copyWith(color: c.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ]),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final MarketReview review;
  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return IosCard(
      padding: const EdgeInsets.all(12),
      radius: IosShapes.radiusLarge,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: c.fill, shape: BoxShape.circle),
            clipBehavior: Clip.antiAlias,
            child: review.author.photoUrl.isNotEmpty
              ? Image.network(review.author.photoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(CupertinoIcons.person_fill, size: 14, color: c.textSecondary))
              : Icon(CupertinoIcons.person_fill, size: 14, color: c.textSecondary),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(review.author.displayName,
            style: t.textStyles.subheadline.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
          ...List.generate(5, (i) {
            final filled = i < review.rating;
            return Icon(
              filled ? CupertinoIcons.star_fill : CupertinoIcons.star,
              size: 12, color: c.yellow,
            );
          }),
        ]),
        if (review.comment.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(review.comment, style: t.textStyles.subheadline.copyWith(color: c.textSecondary)),
        ],
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Review sheet — модальное окно отзыва
// ══════════════════════════════════════════════════════════════════════════

class _ReviewSheet extends StatefulWidget {
  final int initialRating;
  final String initialComment;
  final Future<void> Function(int rating, String comment) onSubmit;
  const _ReviewSheet({
    required this.initialRating,
    required this.initialComment,
    required this.onSubmit,
  });

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late int _rating;
  late TextEditingController _ctrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating;
    _ctrl = TextEditingController(text: widget.initialComment);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSubmit(_rating, _ctrl.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
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
            child: Row(children: [
              Text('Ваш отзыв', style: t.textStyles.headline),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Icon(CupertinoIcons.xmark_circle_fill, size: 28, color: c.textQuaternary),
              ),
            ]),
          ),

          // Stars
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children:
              List.generate(5, (i) {
                final filled = i < _rating;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _rating = i + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      filled ? CupertinoIcons.star_fill : CupertinoIcons.star,
                      size: 32, color: c.yellow,
                    ),
                  ),
                );
              })),
          ),
          Center(child: Text('$_rating из 5',
            style: t.textStyles.footnote.copyWith(color: c.textSecondary))),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: IosField(
              controller: _ctrl,
              label: 'Комментарий (опционально)',
              placeholder: 'Что понравилось, что нет…',
              maxLines: 4,
            ),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(_error!, style: t.textStyles.footnote.copyWith(color: c.red)),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: IosButton(
              label: 'Отправить',
              style: IosButtonStyle.primary,
              loading: _saving,
              onPressed: _saving ? null : _submit,
            ),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════

class _ErrorBlock extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBlock({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 44, color: c.red),
        const SizedBox(height: 12),
        Text('Не удалось загрузить', style: t.textStyles.title3),
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
    );
  }
}

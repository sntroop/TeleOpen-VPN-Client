// lib/screens/market_detail_screen.dart
//
// Детальная страница подписки: описание, отзывы, рейтинг звёздами,
// live-статистика, кнопка «Добавить себе» (загружает узлы и сохраняет в группы),
// возможность оставить/изменить отзыв (требует авторизации).

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ios_theme.dart';
import '../main.dart';
import '../models/market.dart';
import '../models/vpn_node.dart';
import '../models/mtproto_proxy.dart';
import '../logic/market_api.dart';
import '../logic/parsers.dart';
import '../logic/launched_nodes.dart';
import '../logic/device_id.dart';
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
  bool _buying = false;
  double? _balance; // внутренний баланс (null — не залогинен / не загрузился)

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
      if (userId != null && d.isPaid) _refreshBalance();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _refreshBalance() async {
    try {
      final b = await MarketApi.myBalance();
      if (mounted) setState(() => _balance = b);
    } catch (_) {
      // Баланс — вспомогательная фича; без него покупка по СБП всё равно работает.
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

  Future<void> _reportGroup() async {
    final state0 = AppStateScope.of(context, listen: false);
    if (state0.currentUser == null) {
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ));
      if (ok != true || state0.currentUser == null) return;
    }
    if (!mounted) return;

    // Жаловаться можно только на подписку, которую добавил себе И хотя бы раз
    // запускал её сервер — отсекает фейковые жалобы с витрины.
    final group = state0.groups
        .where((g) => g.id == 'market_${widget.groupId}')
        .cast<VpnGroup?>()
        .firstOrNull;
    if (group == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Сначала добавьте подписку себе, чтобы пожаловаться.'),
      ));
      return;
    }
    final launchedAny = group.nodes.any(
        (n) => LaunchedNodes.isLaunched(state0.prefs, n.reportUriHash));
    if (!launchedAny) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Сначала запустите хотя бы один сервер подписки — '
            'жаловаться можно только на то, чем вы пользовались.'),
      ));
      return;
    }

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dctx) => CupertinoAlertDialog(
        title: const Text('Пожаловаться на подписку?'),
        content: const Text('Сообщите, если подписка нерабочая, мошенническая '
            'или нарушает правила. Модерация проверит её.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('Пожаловаться'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await MarketApi.reportGroup(groupId: widget.groupId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Жалоба отправлена. Спасибо!')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось отправить жалобу. Попробуйте позже.')),
      );
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
      final state = AppStateScope.of(context, listen: false);

      if (_detail!.isMtProto) {
        // MTProto-группа: ноды — это tg://proxy / t.me/proxy ссылки, их нельзя
        // парсить как VpnNode. Разбираем в MtProtoProxy и кладём в отдельную
        // группу Telegram-прокси.
        final proxies = <MtProtoProxy>[];
        for (final mn in res.nodes) {
          final p = MtProtoProxy.tryParse(mn.uri);
          if (p != null) proxies.add(p);
        }
        if (proxies.isEmpty) {
          throw Exception('Не удалось распарсить прокси');
        }
        state.addMarketMtProtoGroup(
          marketId: widget.groupId,
          title: res.name,
          proxies: proxies,
        );
      } else {
        // Превращаем URI в VpnNode и добавляем как новую группу
        final nodes = <VpnNode>[];
        for (final mn in res.nodes) {
          final n = parseUri(mn.uri);
          if (n != null) {
            // Точный хэш ноды от бэка — нужен для жалобы на конкретный сервер.
            n.marketUriHash = mn.uriHash;
            nodes.add(n);
          }
        }
        if (nodes.isEmpty) {
          throw Exception('Не удалось распарсить серверы');
        }
        state.addMarketGroup(
          marketId: widget.groupId,
          title: res.name,
          nodes: nodes,
          iconUrl: res.iconUrl,
          contactUrl: res.contactUrl,
          description: _detail?.description,
        );
      }

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

  // ─── Покупка платной подписки по СБП ──────────────────────────────────────

  /// Добавляет купленную подписку как живую ссылку /market/paid_sub/<code>:
  /// сервер сам считает срок/трафик/устройства и перестаёт отдавать ноды,
  /// когда подписка истекла — при обновлении она «гаснет» у покупателя.
  Future<void> _addPurchased(MarketPurchase p) async {
    final subUrl = p.subUrl;
    if (subUrl == null) return;
    final state = AppStateScope.of(context, listen: false);
    final dh = await DeviceId.get();
    final sep = subUrl.contains('?') ? '&' : '?';
    final err = await state.addSubscription(
      url: '$subUrl${sep}did=$dh',
      title: _detail?.name,
      description: _detail?.description,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err == null
          ? '«${_detail?.name}» добавлена в твои подписки'
          : 'Ошибка: $err'),
    ));
    if (err == null) Navigator.of(context).pop(true);
  }

  /// Логин (если надо) → шит выбора тарифа/устройств/оплаты → платёж.
  Future<void> _buy() async {
    if (_buying || _detail == null) return;
    final d = _detail!;
    final state0 = AppStateScope.of(context, listen: false);
    if (state0.currentUser == null) {
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ));
      if (ok != true || state0.currentUser == null) return;
      await _refreshBalance();
    }
    if (!mounted) return;

    final renewal = d.myPurchase != null && d.myPurchase!.status == 'active';
    final choice = await showModalBottomSheet<_BuyChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PurchaseSheet(
        detail: d,
        balance: _balance,
        isRenewal: renewal,
      ),
    );
    if (choice == null || !mounted) return;

    await _executeBuy(
      action: renewal ? 'renew' : 'purchase',
      tariffDays: choice.tariffDays,
      devices: choice.devices,
      payMethod: choice.payMethod,
      successText: renewal ? 'Подписка продлена!' : 'Оплата прошла! Подписка активирована.',
    );
  }

  /// Докупка трафика или устройств к активной подписке.
  Future<void> _topup() async {
    if (_buying || _detail == null) return;
    final d = _detail!;
    final choice = await showModalBottomSheet<_TopupChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TopupSheet(detail: d, balance: _balance),
    );
    if (choice == null || !mounted) return;

    await _executeBuy(
      action: choice.isTraffic ? 'extra_traffic' : 'extra_device',
      gb: choice.isTraffic ? choice.amount : null,
      count: choice.isTraffic ? null : choice.amount,
      payMethod: choice.payMethod,
      successText: choice.isTraffic
          ? 'Трафик докуплен (+${choice.amount} ГБ)'
          : 'Устройства добавлены (+${choice.amount})',
    );
  }

  /// Общий хвост оплаты: balance — мгновенно, sbp — ссылка + ожидание.
  Future<void> _executeBuy({
    String action = 'purchase',
    int? tariffDays,
    int? devices,
    int? gb,
    int? count,
    required String payMethod,
    required String successText,
  }) async {
    setState(() => _buying = true);
    try {
      final res = await MarketApi.buyGroup(
        widget.groupId,
        action: action,
        tariffDays: tariffDays,
        devices: devices,
        gb: gb,
        count: count,
        payMethod: payMethod,
      );
      if (!mounted) return;

      MarketPurchase? purchase;
      if (res.paidWithBalance) {
        purchase = res.purchase;
        if (res.balanceRub != null) setState(() => _balance = res.balanceRub);
      } else {
        await launchUrl(Uri.parse(res.url), mode: LaunchMode.externalApplication);
        if (!mounted) return;
        // Ждём подтверждение оплаты (поллинг бэка, тот сам спрашивает Platega).
        purchase = await showCupertinoDialog<MarketPurchase>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _PaymentWaitDialog(paymentId: res.paymentId),
        );
      }
      if (!mounted) return;

      if (purchase != null && purchase.isActive) {
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successText)));
        if (action == 'purchase') await _addPurchased(purchase);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _buying = false);
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
          // Пожаловаться на подписку
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _reportGroup,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(CupertinoIcons.flag, size: 22, color: c.textSecondary),
            ),
          ),
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

            // ── Платная подписка: условия ─────────────────────────────
            if (d.isPaid)
              SliverToBoxAdapter(child: _PaidInfoCard(detail: d)),

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
        child: _buildCta(t, c, d),
      ),
    ]);
  }

  /// Нижняя кнопка: бесплатная — «Добавить», платная — «Купить»/«Продлить»
  /// (+ «Добавить»/«Докупить» при активной покупке).
  Widget _buildCta(IosThemeData t, IosColors c, MarketDetail d) {
    if (!d.isPaid) {
      return IosButton(
        label: 'Добавить в мои подписки',
        style: IosButtonStyle.primary,
        leadingIcon: CupertinoIcons.cloud_download_fill,
        loading: _adding,
        onPressed: _adding ? null : _addToMy,
      );
    }

    final mp = d.myPurchase;
    final minPrice = d.minPriceRub;
    final priceLabel = minPrice == null
        ? '?'
        : (d.tariffs.length > 1 ? 'от ${_rubFmt(minPrice)}' : _rubFmt(minPrice));
    final canTopup = (d.extraGbPriceRub ?? 0) > 0 || (d.extraDevicePriceRub ?? 0) > 0;

    if (mp != null && mp.isActive) {
      final left = mp.expiresAt != null ? 'Осталось ${mp.daysLeft} дн.' : 'Активна';
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Куплено · $left',
              style: t.textStyles.footnote.copyWith(color: c.green)),
        ),
        Row(children: [
          Expanded(child: IosButton(
            label: 'Добавить',
            style: IosButtonStyle.primary,
            onPressed: () => _addPurchased(mp),
          )),
          const SizedBox(width: 8),
          Expanded(child: IosButton(
            label: 'Продлить',
            style: IosButtonStyle.secondary,
            loading: _buying,
            onPressed: _buying ? null : _buy,
          )),
          if (canTopup) ...[
            const SizedBox(width: 8),
            Expanded(child: IosButton(
              label: 'Докупить',
              style: IosButtonStyle.secondary,
              loading: _buying,
              onPressed: _buying ? null : _topup,
            )),
          ],
        ]),
      ]);
    }

    final expired = mp != null && !mp.isActive && mp.status == 'active';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (expired)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Подписка истекла — продли, чтобы продолжить',
              style: t.textStyles.footnote.copyWith(color: c.orange)),
        ),
      IosButton(
        label: expired ? 'Продлить · $priceLabel ₽' : 'Купить · $priceLabel ₽',
        style: IosButtonStyle.primary,
        leadingIcon: CupertinoIcons.money_rubl_circle_fill,
        loading: _buying,
        onPressed: _buying ? null : _buy,
      ),
    ]);
  }
}

/// «199» или «199.50» — без копеек, когда они нулевые.
String _rubFmt(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

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
          cell(CupertinoIcons.cloud_fill, detail.isMtProto ? 'прокси' : 'серверов', '${detail.nodesCount}'),
          Container(width: 0.5, height: 50, color: c.separator),
          // «онлайн»: берём максимум из live-поллинга и activeSessions, который
          // показывает карточка. Иначе при live=0 (поллинг ещё не пришёл/вернул 0)
          // деталь показывала 0, хотя на карточке было N — расхождение из бага.
          cell(
            CupertinoIcons.person_2_fill,
            'онлайн',
            '${(live?.activeUsers15m ?? 0) > detail.activeSessions ? live!.activeUsers15m : detail.activeSessions}',
            color: ((live?.activeUsers15m ?? 0) > 0 || detail.activeSessions > 0) ? c.green : null,
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
// Платная подписка: карточка условий + диалог ожидания оплаты
// ══════════════════════════════════════════════════════════════════════════

class _PaidInfoCard extends StatelessWidget {
  final MarketDetail detail;
  const _PaidInfoCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final d = detail;
    final extraDev = d.extraDevicePriceRub ?? 0;
    final extraGb = d.extraGbPriceRub ?? 0;

    Widget row(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 16, color: c.textSecondary),
        const SizedBox(width: 8),
        Text(label, style: t.textStyles.subheadline.copyWith(color: c.textSecondary)),
        const Spacer(),
        Text(value, style: t.textStyles.subheadline.copyWith(fontWeight: FontWeight.w600)),
      ]),
    );

    final minPrice = d.minPriceRub;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: IosCard(
        radius: IosShapes.radiusLarge,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(CupertinoIcons.money_rubl_circle_fill, size: 20, color: c.green),
            const SizedBox(width: 8),
            Text('Платная подписка', style: t.textStyles.headline),
            const Spacer(),
            if (minPrice != null)
              Text(
                d.tariffs.length > 1 ? 'от ${_rubFmt(minPrice)} ₽' : '${_rubFmt(minPrice)} ₽',
                style: t.textStyles.title3.copyWith(color: c.green, fontWeight: FontWeight.w700),
              ),
          ]),
          const SizedBox(height: 8),

          // Тарифная сетка
          if (d.tariffs.isNotEmpty) ...[
            for (final tr in d.tariffs)
              row(CupertinoIcons.calendar, tr.periodLabel, '${_rubFmt(tr.priceRub)} ₽'),
            Container(height: 0.5, color: c.separator,
                margin: const EdgeInsets.symmetric(vertical: 6)),
          ] else
            row(CupertinoIcons.calendar, 'Срок', '${d.paidDurationDays ?? '—'} дней'),

          row(CupertinoIcons.arrow_up_arrow_down_circle, 'Трафик на период',
              d.paidTrafficGb == null ? 'Безлимит' : '${d.paidTrafficGb} ГБ'),
          row(
            CupertinoIcons.device_phone_portrait,
            'Устройства',
            extraDev > 0
                ? '1 включено, +${_rubFmt(extraDev)} ₽/шт'
                  '${d.paidDeviceLimit != null ? ' (до ${d.paidDeviceLimit})' : ''}'
                : (d.paidDeviceLimit == null ? 'Без ограничений' : 'до ${d.paidDeviceLimit}'),
          ),
          if (extraGb > 0)
            row(CupertinoIcons.plus_circle, 'Докупка трафика', '${_rubFmt(extraGb)} ₽/ГБ'),
          const SizedBox(height: 4),
          Text('Оплата по СБП или с внутреннего баланса. По истечении срока подписка блокируется до продления.',
              style: t.textStyles.caption1.copyWith(color: c.textTertiary)),
        ]),
      ),
    );
  }
}

/// Выбор покупателя в шите покупки/продления.
class _BuyChoice {
  final int tariffDays;
  final int devices; // всего устройств (1 = только базовое)
  final String payMethod; // sbp | balance
  const _BuyChoice({
    required this.tariffDays,
    required this.devices,
    required this.payMethod,
  });
}

/// Шит покупки/продления: тариф → устройства → способ оплаты → итог.
class _PurchaseSheet extends StatefulWidget {
  final MarketDetail detail;
  final double? balance;
  final bool isRenewal;
  const _PurchaseSheet({
    required this.detail,
    required this.balance,
    required this.isRenewal,
  });

  @override
  State<_PurchaseSheet> createState() => _PurchaseSheetState();
}

class _PurchaseSheetState extends State<_PurchaseSheet> {
  late List<MarketTariff> _tariffs;
  late int _tariffIdx;
  late int _devices;
  String _payMethod = 'sbp';

  @override
  void initState() {
    super.initState();
    final d = widget.detail;
    _tariffs = d.tariffs.isNotEmpty
        ? d.tariffs
        : [MarketTariff(days: d.paidDurationDays ?? 30, priceRub: d.minPriceRub ?? 0)];
    // По умолчанию — самый дешёвый тариф (он же показан на кнопке «Купить»).
    _tariffIdx = 0;
    for (int i = 1; i < _tariffs.length; i++) {
      if (_tariffs[i].priceRub < _tariffs[_tariffIdx].priceRub) _tariffIdx = i;
    }
    // При продлении сохраняем текущее число устройств покупателя.
    _devices = widget.isRenewal ? (d.myPurchase?.devices ?? 1) : 1;
  }

  double get _extraDev => widget.detail.extraDevicePriceRub ?? 0;
  int get _maxDevices {
    final lim = widget.detail.paidDeviceLimit;
    if (_extraDev <= 0) return 1;
    return (lim == null || lim < 1) ? 1000 : lim;
  }

  double get _total =>
      _tariffs[_tariffIdx].priceRub + (_devices - 1) * _extraDev;

  bool get _balanceEnough => (widget.balance ?? 0) >= _total;

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return Container(
      margin: EdgeInsets.fromLTRB(8, 0, 8, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: c.bgSecondary,
        borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 6),
            width: 36, height: 4,
            decoration: BoxDecoration(color: c.textQuaternary, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(children: [
              Text(widget.isRenewal ? 'Продление подписки' : 'Покупка подписки',
                  style: t.textStyles.headline),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Icon(CupertinoIcons.xmark_circle_fill, size: 28, color: c.textQuaternary),
              ),
            ]),
          ),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // ── Тариф ──
                const _SheetSectionTitle('Тариф'),
                for (int i = 0; i < _tariffs.length; i++)
                  _SelectableRow(
                    selected: i == _tariffIdx,
                    onTap: () => setState(() => _tariffIdx = i),
                    title: _tariffs[i].periodLabel,
                    trailing: '${_rubFmt(_tariffs[i].priceRub)} ₽',
                  ),

                // ── Устройства ──
                if (_extraDev > 0) ...[
                  const _SheetSectionTitle('Устройства'),
                  _StepperRow(
                    value: _devices,
                    min: 1,
                    max: _maxDevices,
                    label: _devices == 1
                        ? '1 устройство (включено)'
                        : '$_devices устройств'
                          ' (+${_rubFmt((_devices - 1) * _extraDev)} ₽)',
                    onChanged: (v) => setState(() => _devices = v),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Первое устройство бесплатно, каждое следующее +${_rubFmt(_extraDev)} ₽.',
                      style: t.textStyles.caption1.copyWith(color: c.textTertiary),
                    ),
                  ),
                ],

                // ── Оплата ──
                const _SheetSectionTitle('Оплата'),
                _SelectableRow(
                  selected: _payMethod == 'sbp',
                  onTap: () => setState(() => _payMethod = 'sbp'),
                  title: 'СБП (банковское приложение)',
                ),
                _SelectableRow(
                  selected: _payMethod == 'balance',
                  enabled: _balanceEnough,
                  onTap: () => setState(() => _payMethod = 'balance'),
                  title: 'Баланс · ${_rubFmt(widget.balance ?? 0)} ₽',
                  trailing: _balanceEnough ? null : 'не хватает',
                ),
              ]),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: IosButton(
              label: '${widget.isRenewal ? 'Продлить' : 'Купить'} · ${_rubFmt(_total)} ₽',
              style: IosButtonStyle.primary,
              leadingIcon: CupertinoIcons.money_rubl_circle_fill,
              onPressed: () => Navigator.of(context).pop(_BuyChoice(
                tariffDays: _tariffs[_tariffIdx].days,
                devices: _devices,
                payMethod: _payMethod,
              )),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Выбор в шите докупки.
class _TopupChoice {
  final bool isTraffic; // true — гигабайты, false — устройства
  final int amount;
  final String payMethod;
  const _TopupChoice({
    required this.isTraffic,
    required this.amount,
    required this.payMethod,
  });
}

/// Шит докупки трафика/устройств к активной подписке.
class _TopupSheet extends StatefulWidget {
  final MarketDetail detail;
  final double? balance;
  const _TopupSheet({required this.detail, required this.balance});

  @override
  State<_TopupSheet> createState() => _TopupSheetState();
}

class _TopupSheetState extends State<_TopupSheet> {
  late bool _isTraffic;
  int _amount = 1;
  String _payMethod = 'sbp';

  bool get _trafficAvail =>
      (widget.detail.extraGbPriceRub ?? 0) > 0 &&
      widget.detail.myPurchase?.trafficTotal != null;
  bool get _deviceAvail => (widget.detail.extraDevicePriceRub ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    _isTraffic = _trafficAvail;
  }

  int get _maxAmount {
    if (_isTraffic) return 10000;
    final lim = widget.detail.paidDeviceLimit;
    final have = widget.detail.myPurchase?.devices ?? 1;
    if (lim == null || lim < 1) return 100;
    final room = lim - have;
    return room < 1 ? 0 : room;
  }

  double get _unit => _isTraffic
      ? (widget.detail.extraGbPriceRub ?? 0)
      : (widget.detail.extraDevicePriceRub ?? 0);

  double get _total => _amount * _unit;
  bool get _balanceEnough => (widget.balance ?? 0) >= _total;

  void _switchKind(bool traffic) => setState(() {
        _isTraffic = traffic;
        _amount = 1;
      });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final noRoom = !_isTraffic && _maxAmount == 0;

    return Container(
      margin: EdgeInsets.fromLTRB(8, 0, 8, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: c.bgSecondary,
        borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 6),
            width: 36, height: 4,
            decoration: BoxDecoration(color: c.textQuaternary, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(children: [
              Text('Докупка', style: t.textStyles.headline),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Icon(CupertinoIcons.xmark_circle_fill, size: 28, color: c.textQuaternary),
              ),
            ]),
          ),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_trafficAvail && _deviceAvail) ...[
                  const _SheetSectionTitle('Что докупить'),
                  _SelectableRow(
                    selected: _isTraffic,
                    onTap: () => _switchKind(true),
                    title: 'Трафик',
                    trailing: '${_rubFmt(widget.detail.extraGbPriceRub!)} ₽/ГБ',
                  ),
                  _SelectableRow(
                    selected: !_isTraffic,
                    onTap: () => _switchKind(false),
                    title: 'Устройства',
                    trailing: '${_rubFmt(widget.detail.extraDevicePriceRub!)} ₽/шт',
                  ),
                ],

                _SheetSectionTitle(_isTraffic ? 'Сколько ГБ' : 'Сколько устройств'),
                if (noRoom)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('Достигнут лимит устройств этой подписки.',
                        style: t.textStyles.subheadline.copyWith(color: c.orange)),
                  )
                else
                  _StepperRow(
                    value: _amount,
                    min: 1,
                    max: _maxAmount,
                    label: _isTraffic ? '+$_amount ГБ' : '+$_amount устр.',
                    onChanged: (v) => setState(() => _amount = v),
                  ),

                const _SheetSectionTitle('Оплата'),
                _SelectableRow(
                  selected: _payMethod == 'sbp',
                  onTap: () => setState(() => _payMethod = 'sbp'),
                  title: 'СБП (банковское приложение)',
                ),
                _SelectableRow(
                  selected: _payMethod == 'balance',
                  enabled: _balanceEnough,
                  onTap: () => setState(() => _payMethod = 'balance'),
                  title: 'Баланс · ${_rubFmt(widget.balance ?? 0)} ₽',
                  trailing: _balanceEnough ? null : 'не хватает',
                ),
              ]),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: IosButton(
              label: 'Докупить · ${_rubFmt(_total)} ₽',
              style: IosButtonStyle.primary,
              leadingIcon: CupertinoIcons.plus_circle_fill,
              onPressed: noRoom
                  ? null
                  : () => Navigator.of(context).pop(_TopupChoice(
                        isTraffic: _isTraffic,
                        amount: _amount,
                        payMethod: _payMethod,
                      )),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Мелкие кирпичи шитов покупки ─────────────────────────────────────────────

class _SheetSectionTitle extends StatelessWidget {
  final String text;
  const _SheetSectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Text(text.toUpperCase(),
          style: t.textStyles.footnote.copyWith(color: c.textSecondary, letterSpacing: 0.5)),
    );
  }
}

class _SelectableRow extends StatelessWidget {
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final String title;
  final String? trailing;
  const _SelectableRow({
    required this.selected,
    required this.onTap,
    required this.title,
    this.trailing,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final fg = enabled ? c.textPrimary : c.textTertiary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: c.fill,
          borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
          border: Border.all(
            color: selected ? c.green : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(children: [
          Icon(
            selected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
            size: 20, color: selected ? c.green : c.textQuaternary,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: t.textStyles.body.copyWith(color: fg))),
          if (trailing != null)
            Text(trailing!,
                style: t.textStyles.subheadline
                    .copyWith(color: enabled ? c.textSecondary : c.textTertiary, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final String label;
  final ValueChanged<int> onChanged;
  const _StepperRow({
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    Widget btn(IconData icon, bool enabled, VoidCallback onTap) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Icon(icon, size: 30, color: enabled ? c.textPrimary : c.textQuaternary),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.fill,
        borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
      ),
      child: Row(children: [
        Expanded(child: Text(label, style: t.textStyles.body)),
        btn(CupertinoIcons.minus_circle, value > min, () => onChanged(value - 1)),
        const SizedBox(width: 14),
        btn(CupertinoIcons.plus_circle, value < max, () => onChanged(value + 1)),
      ]),
    );
  }
}

/// Диалог «ждём оплату»: поллит /market/purchase_status каждые 4 секунды,
/// закрывается сам при подтверждении/отмене платежа или вручную кнопкой.
class _PaymentWaitDialog extends StatefulWidget {
  final String paymentId;
  const _PaymentWaitDialog({required this.paymentId});

  @override
  State<_PaymentWaitDialog> createState() => _PaymentWaitDialogState();
}

class _PaymentWaitDialogState extends State<_PaymentWaitDialog> {
  Timer? _timer;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    _ticks++;
    // Платёжная ссылка живёт 15 минут — дольше ждать нет смысла.
    if (_ticks > 230) {
      if (mounted) Navigator.of(context).pop(null);
      return;
    }
    try {
      final r = await MarketApi.purchaseStatus(widget.paymentId);
      if (!mounted) return;
      if (r.paymentStatus == 'confirmed') {
        Navigator.of(context).pop(r.purchase);
      } else if (r.paymentStatus == 'canceled' ||
          r.paymentStatus == 'chargebacked') {
        Navigator.of(context).pop(null);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Платёж отменён')));
      }
    } catch (_) {
      // сетевые сбои в поллинге штатны
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: const Text('Ожидаем оплату'),
      content: const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Column(children: [
          CupertinoActivityIndicator(),
          SizedBox(height: 8),
          Text('Оплати по СБП в банковском приложении.\n'
              'Подписка активируется автоматически.'),
        ]),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Отмена'),
        ),
      ],
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

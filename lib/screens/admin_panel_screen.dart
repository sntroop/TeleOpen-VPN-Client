// lib/screens/admin_panel_screen.dart
//
// Модераторская панель: список всех подписок, удаление, бан/разбан автора,
// редактирование названия/описания/иконки/тегов/серверов.
// Доступна только если user.isAdmin == true.
//
// Корень библиотеки admin_panel_screen. Здесь сам экран и его State; карточка
// списка, экран редактирования и виджеты бейджей вынесены в part-файлы
// screens/admin/. Путь файла не менялся → импорты не трогаются.

library admin_panel_screen;

import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../ios_theme.dart';
import '../models/market.dart';
import '../logic/market_api.dart';
import 'market_detail_screen.dart';

part 'admin/item_card.dart';
part 'admin/edit_screen.dart';
part 'admin/badges.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  List<AdminMarketItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }


  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await MarketApi.adminList();
      if (!mounted) return;
      setState(() { _items = result.items; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ─── Установить / снять TeleOpen-бейдж ─────────────────────────────────

  Future<void> _setBadgeResult(AdminMarketItem item, _BadgeResult result) async {
    final badgeApiValue = result.remove ? null : result.badge?.apiValue;
    try {
      await MarketApi.adminSetBadge(
        groupId: item.id,
        badge: badgeApiValue,
      );
      if (!mounted) return;
      setState(() {
        _items = _items.map((i) {
          if (i.id == item.id) {
            return AdminMarketItem(
              id: i.id, name: i.name, description: i.description,
              iconUrl: i.iconUrl, tags: i.tags, nodesCount: i.nodesCount,
              getsCount: i.getsCount, activeSessions: i.activeSessions,
              ratingAvg: i.ratingAvg, ratingCount: i.ratingCount,
              createdAt: i.createdAt, author: i.author,
              teleOpenBadge: result.remove ? null : result.badge,
              authorTelegramId: i.authorTelegramId,
              authorPublishBanned: i.authorPublishBanned,
              nodes: i.nodes,
            );
          }
          return i;
        }).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.remove ? 'Бейдж снят' : 'Бейдж «${result.badge?.label}» установлен'),
        duration: const Duration(seconds: 2),
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    }
  }

  Future<void> _openBadgePicker(AdminMarketItem item) async {
    final result = await showCupertinoModalPopup<_BadgeResult>(
      context: context,
      builder: (_) => _BadgePickerSheet(current: item.teleOpenBadge),
    );
    if (result == null || !mounted) return;
    await _setBadgeResult(item, result);
  }

  // ─── Удалить подписку ────────────────────────────────────────────────────

  Future<void> _delete(AdminMarketItem item) async {
    final confirmed = await IosDialog.show<bool>(
      context,
      IosDialog(
        title: 'Удалить подписку?',
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
    if (confirmed != true || !mounted) return;

    try {
      await MarketApi.adminDeleteGroup(groupId: item.id);
      if (!mounted) return;
      setState(() => _items.removeWhere((i) => i.id == item.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('«${item.name}» удалена'), duration: const Duration(seconds: 2)),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    }
  }

  // ─── Бан / разбан автора ────────────────────────────────────────────────

  Future<void> _toggleBan(AdminMarketItem item) async {
    final ban = !item.authorPublishBanned;
    final actionLabel = ban ? 'Запретить публикации' : 'Разрешить публикации';
    final actionDesc = ban
        ? '@${item.author.username} больше не сможет публиковать подписки.'
        : '@${item.author.username} снова сможет публиковать подписки.';

    final confirmed = await IosDialog.show<bool>(
      context,
      IosDialog(
        title: actionLabel,
        description: actionDesc,
        actions: [
          IosButton(
            label: actionLabel,
            style: ban ? IosButtonStyle.destructive : IosButtonStyle.primary,
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
    if (confirmed != true || !mounted) return;

    try {
      await MarketApi.adminSetBan(
        targetTelegramId: item.authorTelegramId,
        banned: ban,
      );
      if (!mounted) return;
      // Обновляем флаг у всех подписок этого автора в списке
      setState(() {
        _items = _items.map((i) {
          if (i.authorTelegramId == item.authorTelegramId) {
            return AdminMarketItem(
              id: i.id, name: i.name, description: i.description,
              iconUrl: i.iconUrl, tags: i.tags, nodesCount: i.nodesCount,
              getsCount: i.getsCount, activeSessions: i.activeSessions,
              ratingAvg: i.ratingAvg, ratingCount: i.ratingCount,
              createdAt: i.createdAt, author: i.author,
              authorTelegramId: i.authorTelegramId,
              authorPublishBanned: ban,
              nodes: i.nodes,
            );
          }
          return i;
        }).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ban ? 'Пользователь заблокирован' : 'Блокировка снята'),
          duration: const Duration(seconds: 2),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    }
  }

  // ─── Редактировать подписку ──────────────────────────────────────────────

  Future<void> _edit(AdminMarketItem item) async {
    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => _AdminEditScreen(item: item, ),
      ),
    );
    // После редактирования перезагружаем список
    _load();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

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
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _load,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(CupertinoIcons.refresh, size: 20, color: c.textPrimary),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(children: [
              Icon(CupertinoIcons.shield_fill, size: 22, color: c.textPrimary),
              const SizedBox(width: 8),
              Text('Модерация', style: t.textStyles.largeTitle),
              if (!_loading)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Text('${_items.length}', style: t.textStyles.footnote.copyWith(color: c.textTertiary)),
                ),
            ]),
          ),

          if (_loading)
            const Expanded(child: Center(child: CupertinoActivityIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, style: t.textStyles.body.copyWith(color: c.red), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    IosButton(label: 'Повторить', style: IosButtonStyle.secondary, onPressed: _load),
                  ]),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom + 16),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _AdminItemCard(
                  item: _items[i],
                  onDelete: () => _delete(_items[i]),
                  onToggleBan: () => _toggleBan(_items[i]),
                  onEdit: () => _edit(_items[i]),
                  onSetBadge: () => _openBadgePicker(_items[i]),
                  onTapDetail: () => Navigator.of(context).push(
                    CupertinoPageRoute(builder: (_) => MarketDetailScreen(groupId: _items[i].id)),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

// lib/screens/mtproto_proxy_screen.dart
//
// Экран «Мои MTProto-прокси»: сохранённые группы прокси, пинг, установка
// в Telegram, удаление. Аналог списка VPN-групп, но для Telegram-прокси.

library mtproto_proxy_screen;

import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../ios_theme.dart';
import '../main.dart';
import '../models/mtproto_proxy.dart';
import '../logic/telegram_proxy.dart';
import '../logic/market_api.dart';
import '../widgets/telegram_proxy_sheet.dart';

part 'mtproto_proxy/parts.dart';

class MtProtoProxyScreen extends StatefulWidget {
  const MtProtoProxyScreen({super.key});

  @override
  State<MtProtoProxyScreen> createState() => _MtProtoProxyScreenState();
}

class _MtProtoProxyScreenState extends State<MtProtoProxyScreen> {
  bool _pinging = false;

  Future<void> _pingAll() async {
    final state = AppStateScope.of(context, listen: false);
    final all = <MtProtoProxy>[];
    for (final g in state.mtProtoGroups) {
      all.addAll(g.proxies);
    }
    if (all.isEmpty) return;

    setState(() => _pinging = true);
    await MtProtoProxyPinger.pingAll(
      all,
      onResult: (_, __) {
        if (mounted) setState(() {});
      },
    );
    if (!mounted) return;
    setState(() => _pinging = false);
    state.persistMtProtoGroups();
  }

  Color _pingColor(int? ms, IosColors c) {
    if (ms == null) return c.textTertiary;
    if (ms < 100) return c.green;
    if (ms < 250) return c.orange;
    return c.red;
  }

  void _showShareGroupSheet(BuildContext context, MtProtoProxyGroup group) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareMtProtoGroupSheet(group: group),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final state = AppStateScope.of(context);
    final groups = state.mtProtoGroups;
    final total =
        groups.fold<int>(0, (sum, g) => sum + g.proxies.length);

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
                    Icon(CupertinoIcons.chevron_back,
                        size: 22, color: c.textPrimary),
                    Text(' Назад',
                        style: t.textStyles.body
                            .copyWith(color: c.textPrimary)),
                  ]),
                ),
              ),
              const Spacer(),
              if (total > 0)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _pinging ? null : _pingAll,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: _pinging
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CupertinoActivityIndicator())
                        : Icon(CupertinoIcons.bolt,
                            size: 22, color: c.textPrimary),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(children: [
              Text('MTProto-прокси', style: t.textStyles.largeTitle),
            ]),
          ),

          Expanded(
            child: total == 0
                ? _emptyState(t, c)
                : ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 24),
                    children: groups
                        .map((g) => _buildGroup(g, t, c))
                        .toList(),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _emptyState(IosThemeData t, IosColors c) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.paperplane,
                  size: 48, color: c.textTertiary),
              const SizedBox(height: 16),
              Text('Нет сохранённых прокси',
                  style: t.textStyles.headline),
              const SizedBox(height: 6),
              Text(
                'Добавьте MTProto-прокси на экране «Поделиться» → '
                'таб «MTProto», либо установите из маркета.',
                style: t.textStyles.footnote
                    .copyWith(color: c.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  void _shareProxy(BuildContext context, MtProtoProxy proxy) {
    final link = proxy.buildLink(https: true);
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ссылка скопирована'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, String groupId, MtProtoProxy proxy) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final ctrl = TextEditingController(text: proxy.name);
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
            hintText: proxy.displayName,
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
              final state = AppStateScope.of(context, listen: false);
              final group = state.mtProtoGroups
                  .where((g) => g.id == groupId)
                  .cast<MtProtoProxyGroup?>()
                  .firstOrNull;
              if (group != null) {
                final idx = group.proxies.indexOf(proxy);
                if (idx >= 0) {
                  group.proxies[idx] = proxy.copyWith(name: ctrl.text.trim());
                  state.persistMtProtoGroups();
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

  void _showGroupActions(BuildContext context, MtProtoProxyGroup group) {
    final t = IosTheme.of(context);
    final c = t.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
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
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: c.textQuaternary,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(children: [
              Text(group.title,
                  style: t.textStyles.headline,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
          IosListTile(
            leadingIcon: CupertinoIcons.share,
            leadingIconBg: c.blue,
            title: 'Поделиться группой',
            onTap: () {
              Navigator.of(context).pop();
              _showShareGroupSheet(context, group);
            },
          ),
          Container(margin: const EdgeInsets.only(left: 54), height: 0.5, color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.trash,
            leadingIconBg: c.red,
            title: 'Удалить группу',
            titleColor: c.red,
            onTap: () {
              AppStateScope.of(context, listen: false)
                  .removeMtProtoGroup(group.id);
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _showProxyActions(BuildContext context, String groupId, MtProtoProxy proxy) {
    final t = IosTheme.of(context);
    final c = t.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
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
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: c.textQuaternary,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(children: [
              Text(proxy.displayName,
                  style: t.textStyles.headline,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
          IosListTile(
            leadingIcon: CupertinoIcons.paperplane,
            leadingIconBg: c.fill,
            title: 'Установить в Telegram',
            onTap: () {
              Navigator.of(context).pop();
              showInstallMtProtoProxySheet(context, proxy);
            },
          ),
          Container(margin: const EdgeInsets.only(left: 54), height: 0.5, color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.pencil,
            leadingIconBg: c.fill,
            title: 'Переименовать',
            onTap: () {
              Navigator.of(context).pop();
              _showRenameDialog(context, groupId, proxy);
            },
          ),
          Container(margin: const EdgeInsets.only(left: 54), height: 0.5, color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.wifi,
            leadingIconBg: c.fill,
            title: 'Пингануть',
            onTap: () async {
              final appState = AppStateScope.of(context, listen: false);
              Navigator.of(context).pop();
              final ms = await MtProtoProxyPinger.pingOne(proxy);
              if (!mounted) return;
              proxy.pingMs = ms;
              appState.persistMtProtoGroups();
              setState(() {});
            },
          ),
          Container(margin: const EdgeInsets.only(left: 54), height: 0.5, color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.share,
            leadingIconBg: c.fill,
            title: 'Поделиться',
            onTap: () {
              Navigator.of(context).pop();
              _shareProxy(context, proxy);
            },
          ),
          Container(margin: const EdgeInsets.only(left: 54), height: 0.5, color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.trash,
            leadingIconBg: c.red,
            title: 'Удалить прокси',
            titleColor: c.red,
            onTap: () {
              AppStateScope.of(context, listen: false)
                  .removeMtProtoProxy(groupId, proxy);
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _buildGroup(
      MtProtoProxyGroup g, IosThemeData t, IosColors c) {
    return IosListSection(
      header: g.title,
      // Кнопка «···» рядом с заголовком группы
      headerTrailing: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showGroupActions(context, g),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(CupertinoIcons.share, size: 14, color: c.blue),
            const SizedBox(width: 4),
            Text('Поделиться',
                style: t.textStyles.footnote.copyWith(color: c.blue)),
          ]),
        ),
      ),
      children: g.proxies.map((proxy) {
        return IosListTile(
          leadingIcon: CupertinoIcons.paperplane_fill,
          leadingIconBg: c.blue,
          title: proxy.displayName,
          subtitle: proxy.pingMs != null
              ? '${proxy.kind.label} · ${proxy.pingMs} ms'
              : proxy.kind.label,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (proxy.pingMs != null)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: _pingColor(proxy.pingMs, c),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          onTap: () => showInstallMtProtoProxySheet(context, proxy),
          onLongPress: () => _showProxyActions(context, g.id, proxy),
        );
      }).toList(),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Шит «Поделиться группой MTProto»
//
// Создаёт код на бэкенде (POST /v1/mtproto/create) и показывает результат.
// Получатель вводит код в таб MTProto → «Получить по коду».
// ════════════════════════════════════════════════════════════════════════════


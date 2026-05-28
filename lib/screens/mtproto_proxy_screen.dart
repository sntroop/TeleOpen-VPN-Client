// lib/screens/mtproto_proxy_screen.dart
//
// Экран «Мои MTProto-прокси»: сохранённые группы прокси, пинг, установка
// в Telegram, удаление. Аналог списка VPN-групп, но для Telegram-прокси.

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
              Navigator.of(context).pop();
              final ms = await MtProtoProxyPinger.pingOne(proxy);
              if (!mounted) return;
              proxy.pingMs = ms;
              AppStateScope.of(context, listen: false).persistMtProtoGroups();
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

class _ShareMtProtoGroupSheet extends StatefulWidget {
  final MtProtoProxyGroup group;
  const _ShareMtProtoGroupSheet({required this.group});

  @override
  State<_ShareMtProtoGroupSheet> createState() =>
      _ShareMtProtoGroupSheetState();
}

class _ShareMtProtoGroupSheetState extends State<_ShareMtProtoGroupSheet> {
  late Set<String> _selectedServers;
  late TextEditingController _titleCtrl;

  bool _loading = false;
  String? _code;
  String? _link;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.group.title);
    // По умолчанию — все прокси выбраны
    _selectedServers = widget.group.proxies
        .map((p) => '${p.server}:${p.port}')
        .toSet();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  void _toggle(MtProtoProxy proxy) {
    final key = '${proxy.server}:${proxy.port}';
    setState(() {
      if (_selectedServers.contains(key)) {
        _selectedServers.remove(key);
      } else {
        _selectedServers.add(key);
      }
    });
  }

  bool _isSelected(MtProtoProxy proxy) =>
      _selectedServers.contains('${proxy.server}:${proxy.port}');

  Future<void> _create() async {
    final selected = widget.group.proxies.where(_isSelected).toList();
    if (selected.isEmpty) {
      setState(() => _error = 'Выберите хотя бы один прокси');
      return;
    }

    final title = _titleCtrl.text.trim().isEmpty
        ? widget.group.title
        : _titleCtrl.text.trim();

    setState(() {
      _loading = true;
      _error = null;
      _code = null;
      _link = null;
    });

    try {
      final proxies = selected
          .map((p) => {
                'link': p.buildLink(https: true),
                'displayName': p.displayName,
              })
          .toList();

      final resp = await http
          .post(
            Uri.parse('$kApiBase/v1/mtproto/create'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'title': title, 'proxies': proxies}),
          )
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      final code = (jsonDecode(resp.body) as Map)['code'] as String;

      setState(() {
        _code = code;
        _link = '$kApiBase/mtproto/$code';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Скопировано'),
      duration: Duration(seconds: 1),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      margin: EdgeInsets.fromLTRB(8, 0, 8, bottom + 8),
      decoration: BoxDecoration(
        color: c.bgPrimary,
        borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Ручка
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: c.textQuaternary,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),

            // Заголовок шита
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('Поделиться группой',
                  style: t.textStyles.headline),
            ),

            if (_code != null) ...[
              // ── Результат ──
              _MtProtoCodeCard(
                code: _code!,
                link: _link!,
                onCopyCode: () => _copy(_code!),
                onCopyLink: () => _copy(_link!),
              ),
              const SizedBox(height: 16),
              IosButton(
                label: 'Создать ещё раз',
                style: IosButtonStyle.secondary,
                leadingIcon: CupertinoIcons.refresh,
                onPressed: () => setState(() {
                  _code = null;
                  _link = null;
                }),
              ),
            ] else ...[
              // ── Выбор прокси ──
              IosListSection(
                header:
                    'Прокси (${_selectedServers.length} из ${widget.group.proxies.length})',
                children: [
                  // Выбрать все / снять всё
                  IosListTile(
                    title: _selectedServers.length ==
                            widget.group.proxies.length
                        ? 'Снять выделение'
                        : 'Выбрать все',
                    leadingIcon: _selectedServers.length ==
                            widget.group.proxies.length
                        ? CupertinoIcons.checkmark_square
                        : CupertinoIcons.square,
                    leadingIconBg: c.fill,
                    onTap: () => setState(() {
                      if (_selectedServers.length ==
                          widget.group.proxies.length) {
                        _selectedServers.clear();
                      } else {
                        _selectedServers = widget.group.proxies
                            .map((p) => '${p.server}:${p.port}')
                            .toSet();
                      }
                    }),
                  ),
                  ...widget.group.proxies.map((proxy) {
                    final sel = _isSelected(proxy);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _toggle(proxy),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(proxy.displayName,
                                    style: t.textStyles.body
                                        .copyWith(color: c.textPrimary)),
                                Text(
                                  '${proxy.kind.label} · ${proxy.server}:${proxy.port}',
                                  style: t.textStyles.footnote
                                      .copyWith(color: c.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: sel
                                  ? c.textPrimary
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: sel
                                      ? c.textPrimary
                                      : c.textTertiary,
                                  width: 1.5),
                            ),
                            child: sel
                                ? Icon(CupertinoIcons.check_mark,
                                    size: 13, color: c.bgSecondary)
                                : null,
                          ),
                        ]),
                      ),
                    );
                  }),
                ],
              ),

              const SizedBox(height: 12),

              // Название
              IosListSection(
                header: 'Название для получателя',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: IosField(
                      controller: _titleCtrl,
                      label: 'Название',
                      placeholder: widget.group.title,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.red.withValues(alpha: 0.12),
                    borderRadius:
                        IosShapes.continuous(IosShapes.radiusMedium),
                  ),
                  child: Row(children: [
                    Icon(
                        CupertinoIcons
                            .exclamationmark_triangle_fill,
                        size: 18,
                        color: c.red),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_error!,
                            style: t.textStyles.subheadline
                                .copyWith(color: c.red))),
                  ]),
                ),

              IosButton(
                label: 'Создать код',
                style: IosButtonStyle.primary,
                leadingIcon: CupertinoIcons.share,
                loading: _loading,
                onPressed: _loading ? null : _create,
              ),

              const SizedBox(height: 12),
              Text(
                'Получатель сможет ввести код в таб MTProto → «Получить по коду» и добавить прокси к себе.',
                style:
                    t.textStyles.footnote.copyWith(color: c.textTertiary),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Карточка с готовым кодом ──────────────────────────────────────────────

class _MtProtoCodeCard extends StatelessWidget {
  final String code;
  final String link;
  final VoidCallback onCopyCode;
  final VoidCallback onCopyLink;

  const _MtProtoCodeCard({
    required this.code,
    required this.link,
    required this.onCopyCode,
    required this.onCopyLink,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return IosCard(
      padding: const EdgeInsets.all(20),
      radius: IosShapes.radiusXLarge,
      child: Column(children: [
        Text('Код создан!', style: t.textStyles.headline),
        const SizedBox(height: 20),

        // Большой код
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onCopyCode,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: c.fill,
              borderRadius:
                  IosShapes.continuous(IosShapes.radiusLarge),
            ),
            child: Text(
              code,
              style: t.textStyles.largeTitle.copyWith(
                fontFamily: 'monospace',
                letterSpacing: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Нажми чтобы скопировать',
            style:
                t.textStyles.caption1.copyWith(color: c.textTertiary)),

        const SizedBox(height: 20),
        Container(height: 0.5, color: c.separator),
        const SizedBox(height: 16),

        // Ссылка
        Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: c.fill,
                borderRadius:
                    IosShapes.continuous(IosShapes.radiusMedium),
              ),
              child: Text(
                link,
                style: t.textStyles.footnote.copyWith(
                  color: c.textSecondary,
                  fontFamily: 'monospace',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onCopyLink,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: c.fill, shape: BoxShape.circle),
              child: Icon(CupertinoIcons.doc_on_clipboard,
                  size: 18, color: c.textPrimary),
            ),
          ),
        ]),
      ]),
    );
  }
}

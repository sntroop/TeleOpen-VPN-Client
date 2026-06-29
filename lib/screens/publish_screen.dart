// lib/screens/publish_screen.dart
//
// Экран публикации: выбрать группу из своих подписок, название, описание,
// теги (max 6), иконка (url или загрузить файл).

import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ios_theme.dart';
import '../main.dart';
import '../models/vpn_node.dart';
import '../models/mtproto_proxy.dart';
import '../models/market.dart';
import '../logic/market_api.dart';
import 'author/paid_settings_editor.dart';

class PublishScreen extends StatefulWidget {
  const PublishScreen({super.key});

  @override
  State<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<PublishScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _iconUrlCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _paid = PaidSettingsController();

  VpnGroup? _selectedGroup;
  MtProtoProxyGroup? _selectedMtProtoGroup;
  final Set<String> _selectedTags = {};
  File? _iconFile;
  String? _iconUrl;

  bool _isPaid = false;
  bool? _isSeller; // null — ещё грузим статус
  List<SellerPanel> _panels = [];
  int? _selectedPanelId; // null — общий nodes_json (без персональных UUID)

  bool _publishing = false;
  bool _uploadingIcon = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSellerStatus();
  }

  Future<void> _loadSellerStatus() async {
    try {
      final info = await MarketApi.sellerMe();
      List<SellerPanel> panels = [];
      if (info.isSeller) {
        try { panels = await MarketApi.sellerPanels(); } catch (_) {}
      }
      if (mounted) setState(() { _isSeller = info.isSeller; _panels = panels; });
    } catch (_) {
      if (mounted) setState(() => _isSeller = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _iconUrlCtrl.dispose();
    _contactCtrl.dispose();
    _paid.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    final picker = ImagePicker();
    final xf = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xf == null || !mounted) return;

    setState(() { _uploadingIcon = true; _error = null; });
    try {
      final file = File(xf.path);
      final url = await MarketApi.uploadIcon(file);
      setState(() {
        _iconFile = file;
        _iconUrl = url;
        _iconUrlCtrl.text = url;
        _uploadingIcon = false;
      });
    } catch (e) {
      setState(() { _error = 'Ошибка загрузки иконки: $e'; _uploadingIcon = false; });
    }
  }

  /// Нормализует contact-ссылку (t.me/..., @user, https://t.me/...) → https-URL.
  String _normalizeContact(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    if (s.startsWith('@')) return 'https://t.me/${s.substring(1)}';
    if (s.startsWith('t.me/')) return 'https://$s';
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    return 'https://t.me/$s';
  }

  Future<void> _publish() async {
    final user = AppStateScope.of(context, listen: false).currentUser;
    if (user == null) return;

    final name = _nameCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final group = _selectedGroup;
    final mtGroup = _selectedMtProtoGroup;

    if (name.isEmpty) {
      setState(() => _error = 'Введите название');
      return;
    }
    if (group == null && mtGroup == null) {
      setState(() => _error = 'Выберите группу для публикации');
      return;
    }

    // Собираем nodes + kind в зависимости от источника.
    final String kind;
    final List<Map<String, dynamic>> nodes;
    if (mtGroup != null) {
      kind = 'mtproto';
      // В маркет уходят только валидные MTProto-прокси (с secret). SOCKS5 без
      // секрета бэкенд отбракует — отфильтровываем их заранее.
      nodes = mtGroup.proxies
          .where((p) => p.kind == TelegramProxyKind.mtproto && p.isValid)
          .map((p) => {'uri': p.buildLink(https: true), 'displayName': p.displayName})
          .toList();
      if (nodes.isEmpty) {
        setState(() => _error = 'В группе нет валидных MTProto-прокси для публикации');
        return;
      }
    } else {
      kind = 'vpn';
      if (group!.nodes.isEmpty) {
        setState(() => _error = 'В выбранной группе нет серверов');
        return;
      }
      if (group.nodes.length > 10000) {
        setState(() => _error = 'Максимум 10000 серверов (у тебя ${group.nodes.length})');
        return;
      }
      // displayName = текущее имя ноды (в т.ч. переименованное продавцом). Без
      // него ресейл с переименованием серверов не доезжает до покупателя.
      nodes = group.nodes
          .map((n) => {'uri': n.rawUri, 'displayName': n.name})
          .toList();
    }

    // Платные подписки — только для VPN-групп (персональные UUID и панели не
    // применимы к Telegram-прокси).
    final isPaid = _isPaid && mtGroup == null;
    if (isPaid) {
      final paidError = _paid.validate();
      if (paidError != null) {
        setState(() => _error = paidError);
        return;
      }
    }

    setState(() { _publishing = true; _error = null; });
    try {
      final iconUrl = _iconUrl ?? _iconUrlCtrl.text.trim();
      final id = await MarketApi.publish(
        name: name,
        description: desc,
        iconUrl: iconUrl,
        contactUrl: _normalizeContact(_contactCtrl.text),
        tags: _selectedTags.toList(),
        nodes: nodes,
        kind: kind,
        isPaid: isPaid,
        tariffs: isPaid ? _paid.tariffs : null,
        paidTrafficGb: isPaid ? _paid.trafficGb : null,
        paidDeviceLimit: isPaid ? _paid.deviceLimit : null,
        extraDevicePriceRub: isPaid ? _paid.extraDevicePrice : null,
        extraGbPriceRub: isPaid ? _paid.extraGbPrice : null,
        panelId: isPaid ? _selectedPanelId : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('«$name» опубликована (id $id)'),
        duration: const Duration(seconds: 3),
      ));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() { _error = e.message; _publishing = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _publishing = false; });
    }
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Row(children: [
              Text('Публикация', style: t.textStyles.largeTitle),
            ]),
          ),

          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Выбор группы
                const _SectionHeader(text: 'Группа серверов'),
                IosCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: (state.groups.isEmpty && state.mtProtoGroups.isEmpty)
                      ? [Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text('Нет подписок. Сначала добавь серверы или MTProto-прокси.',
                            style: t.textStyles.body.copyWith(color: c.textSecondary)),
                        )]
                      : [
                          ...state.groups.map((g) {
                            final selected = _selectedGroup?.id == g.id;
                            return IosListTile(
                              title: g.title,
                              subtitle: g.subtitle,
                              trailing: selected
                                ? Icon(CupertinoIcons.check_mark, size: 18, color: c.textPrimary)
                                : null,
                              onTap: () => setState(() {
                                _selectedGroup = g;
                                _selectedMtProtoGroup = null;
                              }),
                            );
                          }),
                          ...state.mtProtoGroups.map((g) {
                            final selected = _selectedMtProtoGroup?.id == g.id;
                            final count = g.proxies
                                .where((p) => p.kind == TelegramProxyKind.mtproto && p.isValid)
                                .length;
                            return IosListTile(
                              title: g.title,
                              subtitle: 'MTProto · $count прокси',
                              trailing: selected
                                ? Icon(CupertinoIcons.check_mark, size: 18, color: c.textPrimary)
                                : null,
                              onTap: () => setState(() {
                                _selectedMtProtoGroup = g;
                                _selectedGroup = null;
                                _isPaid = false; // платно для mtproto нельзя
                              }),
                            );
                          }),
                        ],
                  ),
                ),
                if (_selectedGroup != null) Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    '${_selectedGroup!.nodes.length} серверов будет опубликовано (макс. 10000)',
                    style: t.textStyles.footnote.copyWith(
                      color: _selectedGroup!.nodes.length > 10000 ? c.red : c.textTertiary,
                    ),
                  ),
                ),
                if (_selectedMtProtoGroup != null) Builder(builder: (_) {
                  final count = _selectedMtProtoGroup!.proxies
                      .where((p) => p.kind == TelegramProxyKind.mtproto && p.isValid)
                      .length;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      '$count MTProto-прокси будет опубликовано',
                      style: t.textStyles.footnote.copyWith(
                        color: count == 0 ? c.red : c.textTertiary,
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 20),

                // Название
                const _SectionHeader(text: 'Название'),
                IosCard(
                  padding: const EdgeInsets.all(12),
                  child: IosField(
                    controller: _nameCtrl,
                    label: 'Название подписки',
                    placeholder: 'Например: Быстрые европейские серверы',
                  ),
                ),

                const SizedBox(height: 20),

                // Описание
                const _SectionHeader(text: 'Описание'),
                IosCard(
                  padding: const EdgeInsets.all(12),
                  child: IosField(
                    controller: _descCtrl,
                    label: 'Описание',
                    placeholder: 'Что в подписке, для чего подходит…',
                    maxLines: 5,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: AnimatedBuilder(
                    animation: _descCtrl,
                    builder: (_, __) => Text(
                      '${_descCtrl.text.length} / 4000',
                      style: t.textStyles.caption2.copyWith(
                        color: _descCtrl.text.length > 3800 ? c.orange : c.textTertiary,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Иконка
                const _SectionHeader(text: 'Иконка'),
                IosCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    // Preview
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _pickIcon,
                      child: Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(
                          color: c.fill,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: c.separator),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _uploadingIcon
                          ? Center(child: CupertinoActivityIndicator(color: c.textPrimary))
                          : _iconFile != null
                            ? Image.file(_iconFile!, fit: BoxFit.cover)
                            : _iconUrl != null && _iconUrl!.isNotEmpty
                              ? Image.network(_iconUrl!, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(CupertinoIcons.photo, size: 24, color: c.textTertiary))
                              : Icon(CupertinoIcons.photo, size: 24, color: c.textTertiary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        IosButton(
                          label: 'Выбрать из галереи',
                          style: IosButtonStyle.secondary,
                          leadingIcon: CupertinoIcons.photo,
                          loading: _uploadingIcon,
                          onPressed: _uploadingIcon ? null : _pickIcon,
                        ),
                        const SizedBox(height: 8),
                        IosField(
                          controller: _iconUrlCtrl,
                          label: 'Или вставь URL',
                          placeholder: 'https://...',
                          keyboardType: TextInputType.url,
                          onChanged: (v) => setState(() => _iconUrl = v.trim()),
                        ),
                      ],
                    )),
                  ]),
                ),

                const SizedBox(height: 20),

                // Контакт автора (t.me)
                const _SectionHeader(text: 'Контакт (Telegram)'),
                IosCard(
                  padding: const EdgeInsets.all(12),
                  child: IosField(
                    controller: _contactCtrl,
                    label: 'Ссылка на автора или канал',
                    placeholder: 't.me/yourchannel',
                    keyboardType: TextInputType.url,
                  ),
                ),

                const SizedBox(height: 20),

                // Платная подписка (только с ключом продавца)
                const _SectionHeader(text: 'Платная подписка'),
                IosCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Icon(CupertinoIcons.money_rubl_circle_fill, size: 22, color: c.green),
                      const SizedBox(width: 10),
                      Expanded(child: Text('Выложить платно',
                        style: t.textStyles.body.copyWith(color: c.textPrimary))),
                      CupertinoSwitch(
                        value: _isPaid,
                        onChanged: ((_isSeller ?? false) && _selectedMtProtoGroup == null)
                          ? (v) => setState(() => _isPaid = v)
                          : null,
                      ),
                    ]),
                    if (_selectedMtProtoGroup != null) Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'MTProto-прокси можно публиковать только бесплатно.',
                        style: t.textStyles.footnote.copyWith(color: c.textTertiary),
                      ),
                    ),
                    if (_isSeller == false) Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => launchUrl(Uri.parse('https://t.me/sntroop'),
                            mode: LaunchMode.externalApplication),
                        child: Text(
                          'Для платных публикаций нужен ключ продавца. '
                          'Получить — у @sntroop, активировать — в «Кабинете продавца» в настройках.',
                          style: t.textStyles.footnote.copyWith(color: c.blue),
                        ),
                      ),
                    ),
                    if (_isPaid) ...[
                      const SizedBox(height: 12),
                      PaidSettingsEditor(controller: _paid),
                      if (_panels.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text('Выдача доступа',
                          style: t.textStyles.footnote.copyWith(
                            color: c.textSecondary, letterSpacing: 0.5)),
                        const SizedBox(height: 6),
                        _PanelOption(
                          title: 'Общие настройки',
                          subtitle: 'Один конфиг на всех покупателей',
                          selected: _selectedPanelId == null,
                          onTap: () => setState(() => _selectedPanelId = null),
                        ),
                        for (final p in _panels.where((p) => p.enabled))
                          _PanelOption(
                            title: p.label.isEmpty ? p.kindLabel : p.label,
                            subtitle: '${p.kindLabel} · ${p.host}',
                            selected: _selectedPanelId == p.id,
                            onTap: () => setState(() => _selectedPanelId = p.id),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          _selectedPanelId == null
                            ? 'Все покупатели получат одинаковый конфиг из группы.'
                            : 'Каждому покупателю панель выдаст персональный UUID '
                              'с лимитом устройств и трафика.',
                          style: t.textStyles.footnote.copyWith(color: c.textTertiary),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Покупатель платит по СБП или с внутреннего баланса. По истечении '
                        'срока подписка блокируется до продления; трафик-пакет выдаётся '
                        'на каждый период.',
                        style: t.textStyles.footnote.copyWith(color: c.textTertiary),
                      ),
                    ],
                  ]),
                ),

                const SizedBox(height: 20),

                // Теги
                const _SectionHeader(text: 'Теги'),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Wrap(
                    spacing: 6, runSpacing: 6,
                    children: kMarketValidTags.map((tag) {
                      final sel = _selectedTags.contains(tag);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() {
                            if (sel) {
                              _selectedTags.remove(tag);
                            } else {
                              _selectedTags.add(tag);
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: sel ? c.textPrimary : c.fill,
                            borderRadius: BorderRadius.circular(IosShapes.radiusPill),
                          ),
                          child: Text(tag,
                            style: t.textStyles.footnote.copyWith(
                              color: sel ? c.bgSecondary : c.textPrimary,
                              fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                            )),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 20),

                // Ошибка
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.red.withValues(alpha: 0.12),
                      borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
                    ),
                    child: Row(children: [
                      Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 18, color: c.red),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!,
                        style: t.textStyles.subheadline.copyWith(color: c.red))),
                    ]),
                  ),

                // Submit
                IosButton(
                  label: 'Опубликовать',
                  style: IosButtonStyle.primary,
                  leadingIcon: CupertinoIcons.arrow_up_circle_fill,
                  loading: _publishing,
                  onPressed: _publishing ? null : _publish,
                ),

                const SizedBox(height: 8),
                Text(
                  'После публикации подписка появится в маркетплейсе. Другие пользователи смогут добавить её себе.',
                  style: t.textStyles.footnote.copyWith(color: c.textTertiary),
                  textAlign: TextAlign.center,
                ),

                SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _PanelOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _PanelOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.fill,
          borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
          border: Border.all(
            color: selected ? c.textPrimary : c.separator,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.textStyles.body.copyWith(color: c.textPrimary)),
              const SizedBox(height: 2),
              Text(subtitle, style: t.textStyles.footnote.copyWith(color: c.textTertiary)),
            ],
          )),
          if (selected)
            Icon(CupertinoIcons.check_mark_circled_solid, size: 20, color: c.textPrimary),
        ]),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: t.textStyles.footnote.copyWith(color: c.textSecondary, letterSpacing: 0.5),
      ),
    );
  }
}

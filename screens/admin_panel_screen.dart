import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../ios_theme.dart';
import '../main.dart';
import '../models/market.dart';
import '../logic/market_api.dart';
import 'market_detail_screen.dart';

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

  

  Future<void> _edit(AdminMarketItem item) async {
    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => _AdminEditScreen(item: item, ),
      ),
    );
    
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

class _AdminItemCard extends StatelessWidget {
  final AdminMarketItem item;
  final VoidCallback onDelete;
  final VoidCallback onToggleBan;
  final VoidCallback onEdit;
  final VoidCallback onSetBadge;
  final VoidCallback onTapDetail;

  const _AdminItemCard({
    required this.item,
    required this.onDelete,
    required this.onToggleBan,
    required this.onEdit,
    required this.onSetBadge,
    required this.onTapDetail,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return IosCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: onTapDetail,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: c.fill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.separator),
              ),
              clipBehavior: Clip.antiAlias,
              child: item.iconUrl.isNotEmpty
                  ? Image.network(item.iconUrl, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(CupertinoIcons.antenna_radiowaves_left_right, size: 22, color: c.textTertiary))
                  : Icon(CupertinoIcons.antenna_radiowaves_left_right, size: 22, color: c.textTertiary),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTapDetail,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.name, style: t.textStyles.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [
                  Text(
                    item.author.displayName,
                    style: t.textStyles.footnote.copyWith(color: c.textSecondary),
                  ),
                  if (item.authorPublishBanned) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('БАН', style: t.textStyles.caption2.copyWith(color: c.red, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
                const SizedBox(height: 2),
                Text(
                  '${item.nodesCount} серв. · ${item.getsCount} получ. · ★${item.ratingAvg.toStringAsFixed(1)}',
                  style: t.textStyles.caption2.copyWith(color: c.textTertiary),
                ),
                
                if (item.teleOpenBadge != null) ...[
                  const SizedBox(height: 4),
                  _AdminBadgeChip(badge: item.teleOpenBadge!),
                ],
              ]),
            ),
          ),
        ]),

        const SizedBox(height: 12),

        
        Row(children: [
          Expanded(
            child: IosButton(
              label: 'Изменить',
              style: IosButtonStyle.secondary,
              leadingIcon: CupertinoIcons.pencil,
              onPressed: onEdit,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: IosButton(
              label: item.authorPublishBanned ? 'Разбанить' : 'Забанить',
              style: item.authorPublishBanned ? IosButtonStyle.secondary : IosButtonStyle.secondary,
              leadingIcon: item.authorPublishBanned ? CupertinoIcons.checkmark_shield : CupertinoIcons.hand_raised,
              onPressed: onToggleBan,
            ),
          ),
          const SizedBox(width: 8),
          IosButton(
            label: '',
            style: IosButtonStyle.secondary,
            leadingIcon: item.teleOpenBadge != null
                ? CupertinoIcons.checkmark_seal_fill
                : CupertinoIcons.checkmark_seal,
            onPressed: onSetBadge,
          ),
          const SizedBox(width: 8),
          IosButton(
            label: '',
            style: IosButtonStyle.destructive,
            leadingIcon: CupertinoIcons.trash,
            onPressed: onDelete,
          ),
        ]),
      ]),
    );
  }
}

class _AdminEditScreen extends StatefulWidget {
  final AdminMarketItem item;

  const _AdminEditScreen({required this.item});

  @override
  State<_AdminEditScreen> createState() => _AdminEditScreenState();
}

class _AdminEditScreenState extends State<_AdminEditScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _iconUrlCtrl;
  late Set<String> _selectedTags;
  late List<Map<String, dynamic>> _nodes;

  bool _saving = false;
  bool _uploadingIcon = false;
  String? _error;
  File? _iconFile;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.item.name);
    _descCtrl = TextEditingController(text: widget.item.description);
    _iconUrlCtrl = TextEditingController(text: widget.item.iconUrl);
    _selectedTags = Set<String>.from(widget.item.tags);
    _nodes = widget.item.nodes.map((n) => Map<String, dynamic>.from(n)).toList();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _iconUrlCtrl.dispose();
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
        _iconUrlCtrl.text = url;
        _uploadingIcon = false;
      });
    } catch (e) {
      setState(() { _error = 'Ошибка загрузки: $e'; _uploadingIcon = false; });
    }
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      await MarketApi.adminEditGroup(
        groupId: widget.item.id,
        
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        iconUrl: _iconUrlCtrl.text.trim(),
        tags: _selectedTags.toList(),
        nodes: _nodes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранено'), duration: Duration(seconds: 2)),
      );
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() { _error = e.message; _saving = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _saving = false; });
    }
  }

  Future<void> _editNodeName(int index) async {
    final ctrl = TextEditingController(text: _nodes[index]['displayName'] ?? '');
    final t = IosTheme.of(context);
    await IosDialog.show(
      context,
      IosDialog(
        title: 'Переименовать сервер',
        content: [Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: IosField(
            controller: ctrl,
            label: 'Имя',
            placeholder: 'Название сервера',
          ),
        )],
        actions: [
          IosButton(
            label: 'Сохранить',
            style: IosButtonStyle.primary,
            onPressed: () {
              setState(() => _nodes[index]['displayName'] = ctrl.text.trim());
              Navigator.of(context).pop();
            },
          ),
          IosButton(
            label: 'Отмена',
            style: IosButtonStyle.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  void _removeNode(int index) {
    if (_nodes.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нельзя удалить последний сервер')),
      );
      return;
    }
    setState(() => _nodes.removeAt(index));
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
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(children: [
              Expanded(
                child: Text('Редактирование', style: t.textStyles.largeTitle, overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),

          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom + 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

                
                _SectionLabel(text: 'Название'),
                IosCard(
                  padding: const EdgeInsets.all(12),
                  child: IosField(controller: _nameCtrl, label: 'Название', placeholder: 'Название подписки'),
                ),

                const SizedBox(height: 20),

                
                _SectionLabel(text: 'Описание'),
                IosCard(
                  padding: const EdgeInsets.all(12),
                  child: IosField(
                    controller: _descCtrl,
                    label: 'Описание',
                    placeholder: 'Описание…',
                    maxLines: 4,
                  ),
                ),

                const SizedBox(height: 20),

                
                _SectionLabel(text: 'Иконка'),
                IosCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    GestureDetector(
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
                                : _iconUrlCtrl.text.isNotEmpty
                                    ? Image.network(_iconUrlCtrl.text, fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Icon(CupertinoIcons.photo, size: 24, color: c.textTertiary))
                                    : Icon(CupertinoIcons.photo, size: 24, color: c.textTertiary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                        label: 'URL иконки',
                        placeholder: 'https://…',
                        keyboardType: TextInputType.url,
                      ),
                    ])),
                  ]),
                ),

                const SizedBox(height: 20),

                
                _SectionLabel(text: 'Теги'),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Wrap(
                    spacing: 6, runSpacing: 6,
                    children: kMarketValidTags.map((tag) {
                      final sel = _selectedTags.contains(tag);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() {
                          if (sel) _selectedTags.remove(tag); else _selectedTags.add(tag);
                        }),
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

                
                _SectionLabel(text: 'Серверы (${_nodes.length})'),
                IosCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: List.generate(_nodes.length, (i) {
                      final node = _nodes[i];
                      final name = (node['displayName'] as String?)?.isNotEmpty == true
                          ? node['displayName'] as String
                          : (node['uri'] as String? ?? '').split('@').last.split('#').first;
                      return IosListTile(
                        title: name,
                        subtitle: (node['uri'] as String? ?? '').length > 50
                            ? '${(node['uri'] as String).substring(0, 50)}…'
                            : node['uri'] as String? ?? '',
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          GestureDetector(
                            onTap: () => _editNodeName(i),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(CupertinoIcons.pencil, size: 18, color: c.textSecondary),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _removeNode(i),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(CupertinoIcons.trash, size: 18, color: c.red),
                            ),
                          ),
                        ]),
                      );
                    }),
                  ),
                ),

                const SizedBox(height: 20),

                
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
                      Expanded(child: Text(_error!, style: t.textStyles.subheadline.copyWith(color: c.red))),
                    ]),
                  ),

                IosButton(
                  label: 'Сохранить',
                  style: IosButtonStyle.primary,
                  leadingIcon: CupertinoIcons.checkmark_circle_fill,
                  loading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

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

class _BadgeResult {
  final TeleOpenBadge? badge;
  final bool remove;
  const _BadgeResult({this.badge, this.remove = false});
}

class _AdminBadgeChip extends StatelessWidget {
  final TeleOpenBadge badge;
  const _AdminBadgeChip({required this.badge});

  Color _fg() {
    switch (badge) {
      case TeleOpenBadge.official:  return const Color(0xFF007AFF);
      case TeleOpenBadge.verified:  return const Color(0xFF34C759);
      case TeleOpenBadge.partner:   return const Color(0xFFFF9F0A);
    }
  }

  IconData _icon() {
    switch (badge) {
      case TeleOpenBadge.official:  return CupertinoIcons.star_circle_fill;
      case TeleOpenBadge.verified:  return CupertinoIcons.checkmark_seal_fill;
      case TeleOpenBadge.partner:   return CupertinoIcons.hand_thumbsup_fill;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final fg = _fg();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(IosShapes.radiusPill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_icon(), size: 11, color: fg),
        const SizedBox(width: 4),
        Text(
          badge.label,
          style: t.textStyles.caption2.copyWith(color: fg, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

class _BadgePickerSheet extends StatelessWidget {
  final TeleOpenBadge? current;
  const _BadgePickerSheet({this.current});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    final badges = [
      (TeleOpenBadge.official, CupertinoIcons.star_circle_fill, const Color(0xFF007AFF)),
      (TeleOpenBadge.verified, CupertinoIcons.checkmark_seal_fill, const Color(0xFF34C759)),
      (TeleOpenBadge.partner, CupertinoIcons.hand_thumbsup_fill, const Color(0xFFFF9F0A)),
    ];

    return Container(
      decoration: BoxDecoration(
        color: c.bgSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        
        Center(
          child: Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: c.separator,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Бейдж TeleOpen', style: t.textStyles.headline),
        const SizedBox(height: 4),
        Text('Бейдж отображается на карточке и поднимает подписку наверх списка.',
          style: t.textStyles.footnote.copyWith(color: c.textSecondary)),
        const SizedBox(height: 16),

        
        ...badges.map((entry) {
          final (badge, icon, color) = entry;
          final isSelected = current == badge;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(_BadgeResult(badge: badge)),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.12) : c.fill,
                borderRadius: BorderRadius.circular(IosShapes.radiusMedium),
                border: isSelected ? Border.all(color: color.withValues(alpha: 0.4)) : null,
              ),
              child: Row(children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    badge.label,
                    style: t.textStyles.body.copyWith(
                      color: isSelected ? color : c.textPrimary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(CupertinoIcons.checkmark_circle_fill, size: 18, color: color),
              ]),
            ),
          );
        }),

        
        if (current != null) ...[
          const SizedBox(height: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(const _BadgeResult(remove: true)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: c.fill,
                borderRadius: BorderRadius.circular(IosShapes.radiusMedium),
              ),
              child: Row(children: [
                Icon(CupertinoIcons.xmark_circle, size: 20, color: c.red),
                const SizedBox(width: 12),
                Text('Снять бейдж', style: t.textStyles.body.copyWith(color: c.red)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

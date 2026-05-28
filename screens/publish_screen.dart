import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../ios_theme.dart';
import '../main.dart';
import '../models/vpn_node.dart';
import '../models/market.dart';
import '../logic/market_api.dart';

class PublishScreen extends StatefulWidget {
  const PublishScreen({super.key});

  @override
  State<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<PublishScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _iconUrlCtrl = TextEditingController();

  VpnGroup? _selectedGroup;
  Set<String> _selectedTags = {};
  File? _iconFile;
  String? _iconUrl;

  bool _publishing = false;
  bool _uploadingIcon = false;
  String? _error;

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
        _iconUrl = url;
        _iconUrlCtrl.text = url;
        _uploadingIcon = false;
      });
    } catch (e) {
      setState(() { _error = 'Ошибка загрузки иконки: $e'; _uploadingIcon = false; });
    }
  }

  Future<void> _publish() async {
    final user = AppStateScope.of(context, listen: false).currentUser;
    if (user == null) return;

    final name = _nameCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final group = _selectedGroup;

    if (name.isEmpty) {
      setState(() => _error = 'Введите название');
      return;
    }
    if (group == null) {
      setState(() => _error = 'Выберите группу серверов');
      return;
    }
    if (group.nodes.isEmpty) {
      setState(() => _error = 'В выбранной группе нет серверов');
      return;
    }
    if (group.nodes.length > 10000) {
      setState(() => _error = 'Максимум 10000 серверов (у тебя ${group.nodes.length})');
      return;
    }

    setState(() { _publishing = true; _error = null; });
    try {
      final iconUrl = _iconUrl ?? _iconUrlCtrl.text.trim();
      final nodes = group.nodes.map((n) => {'uri': n.rawUri}).toList();
      final id = await MarketApi.publish(
        name: name,
        description: desc,
        iconUrl: iconUrl,
        tags: _selectedTags.toList(),
        nodes: nodes,
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
                
                _SectionHeader(text: 'Группа серверов'),
                IosCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: state.groups.isEmpty
                      ? [Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text('Нет подписок. Сначала добавь серверы.',
                            style: t.textStyles.body.copyWith(color: c.textSecondary)),
                        )]
                      : state.groups.map((g) {
                          final selected = _selectedGroup?.id == g.id;
                          return IosListTile(
                            title: g.title,
                            subtitle: g.subtitle,
                            trailing: selected
                              ? Icon(CupertinoIcons.check_mark, size: 18, color: c.textPrimary)
                              : null,
                            onTap: () => setState(() => _selectedGroup = g),
                          );
                        }).toList(),
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

                const SizedBox(height: 20),

                
                _SectionHeader(text: 'Название'),
                IosCard(
                  padding: const EdgeInsets.all(12),
                  child: IosField(
                    controller: _nameCtrl,
                    label: 'Название подписки',
                    placeholder: 'Например: Быстрые европейские серверы',
                  ),
                ),

                const SizedBox(height: 20),

                
                _SectionHeader(text: 'Описание'),
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

                
                _SectionHeader(text: 'Иконка'),
                IosCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    
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

                
                _SectionHeader(text: 'Теги'),
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

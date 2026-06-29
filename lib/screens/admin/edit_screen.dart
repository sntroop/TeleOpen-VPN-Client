// lib/screens/admin/edit_screen.dart
// Экран редактирования подписки модератором (название/описание/иконка/теги/
// серверы) + лейбл секции. part of admin_panel_screen.

part of '../admin_panel_screen.dart';

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

                // Название
                const _SectionLabel(text: 'Название'),
                IosCard(
                  padding: const EdgeInsets.all(12),
                  child: IosField(controller: _nameCtrl, label: 'Название', placeholder: 'Название подписки'),
                ),

                const SizedBox(height: 20),

                // Описание
                const _SectionLabel(text: 'Описание'),
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

                // Иконка
                const _SectionLabel(text: 'Иконка'),
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

                // Теги
                const _SectionLabel(text: 'Теги'),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Wrap(
                    spacing: 6, runSpacing: 6,
                    children: kMarketValidTags.map((tag) {
                      final sel = _selectedTags.contains(tag);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() {
                          if (sel) {
                            _selectedTags.remove(tag);
                          } else {
                            _selectedTags.add(tag);
                          }
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

                // Серверы
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

// lib/screens/share/create_tab.dart
// Вкладка CREATE: выбор серверов → создание 6-значного кода/ссылки + карточка
// результата (_CodeCard, общая с MTProto-вкладкой). part of share_screen.

part of '../share_screen.dart';

// ══════════════════════════════════════════════════════════════════════════
// TAB 1: Создать код
// ══════════════════════════════════════════════════════════════════════════

class _CreateTab extends StatefulWidget {
  final VpnGroup? initialGroup;
  const _CreateTab({this.initialGroup});

  @override
  State<_CreateTab> createState() => _CreateTabState();
}

class _CreateTabState extends State<_CreateTab> {
  // Выбранные серверы: groupId → Set<nodeId>
  final Map<String, Set<String>> _selected = {};
  final Map<String, String> _customNames = {}; // nodeId → кастомное имя
  final Set<String> _expandedGroups = {}; // развёрнутые группы (аккордеон)
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _trafficCtrl = TextEditingController(); // ГБ
  DateTime? _expireDate;
  bool _loading = false;
  String? _code;
  String? _link;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialGroup != null) {
      final g = widget.initialGroup!;
      _titleCtrl.text = g.title;
      _selected[g.id] = g.nodes.map((n) => n.id).toSet();
      _expandedGroups.add(g.id); // пришедшую группу сразу разворачиваем
    }
  }

  /// Все выбранные ноды (из всех групп).
  List<VpnNode> _allSelectedNodes(AppState state) {
    final result = <VpnNode>[];
    for (final g in state.groups) {
      final ids = _selected[g.id];
      if (ids == null || ids.isEmpty) continue;
      for (final n in g.nodes) {
        if (ids.contains(n.id)) result.add(n);
      }
    }
    return result;
  }

  int get _totalSelected =>
      _selected.values.fold<int>(0, (sum, ids) => sum + ids.length);

  void _toggleNode(String groupId, String nodeId) {
    setState(() {
      final ids = _selected.putIfAbsent(groupId, () => {});
      if (ids.contains(nodeId)) {
        ids.remove(nodeId);
      } else {
        ids.add(nodeId);
      }
    });
  }

  void _toggleGroup(VpnGroup g) {
    setState(() {
      final ids = _selected.putIfAbsent(g.id, () => {});
      if (ids.length == g.nodes.length) {
        ids.clear();
      } else {
        ids.addAll(g.nodes.map((n) => n.id));
      }
    });
  }

  /// Снять выбор со всех серверов всех групп разом.
  void _deselectAll() {
    setState(() => _selected.clear());
  }

  /// Выбрать все серверы всех групп разом.
  void _selectAll(AppState state) {
    setState(() {
      for (final g in state.groups) {
        _selected[g.id] = g.nodes.map((n) => n.id).toSet();
      }
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _trafficCtrl.dispose();
    super.dispose();
  }

  void _showRenameNodeDialog(BuildContext context, VpnNode node) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final ctrl = TextEditingController(text: _customNames[node.id] ?? node.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Переименовать', style: t.textStyles.headline),
        content: IosField(
          controller: ctrl,
          label: 'Новое название',
          placeholder: node.name,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Отмена', style: t.textStyles.body.copyWith(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final val = ctrl.text.trim();
              setState(() {
                if (val.isEmpty || val == node.name) {
                  _customNames.remove(node.id);
                } else {
                  _customNames[node.id] = val;
                }
              });
              Navigator.of(ctx).pop();
            },
            child: Text('Сохранить', style: t.textStyles.body.copyWith(color: c.textPrimary)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickExpireDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expireDate ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() => _expireDate = picked);
    }
  }

  Future<void> _create() async {
    final state = AppStateScope.of(context, listen: false);
    final selected = _allSelectedNodes(state);

    if (selected.isEmpty) {
      setState(() => _error = 'Выберите хотя бы один сервер');
      return;
    }

    final title = _titleCtrl.text.trim().isEmpty ? 'Мои серверы' : _titleCtrl.text.trim();
    final description = _descCtrl.text.trim();

    // Парсим трафик (ГБ → байты)
    int? trafficTotal;
    final gbText = _trafficCtrl.text.trim();
    if (gbText.isNotEmpty) {
      final gb = double.tryParse(gbText);
      if (gb != null && gb > 0) {
        trafficTotal = (gb * 1024 * 1024 * 1024).toInt();
      }
    }

    // Expire → unix timestamp
    int? trafficExpire;
    if (_expireDate != null) {
      trafficExpire = _expireDate!.millisecondsSinceEpoch ~/ 1000;
    }

    setState(() { _loading = true; _error = null; _code = null; _link = null; });
    try {
      final nodes = selected.map((n) => {
        'uri': n.rawUri,
        'displayName': _customNames[n.id] ?? n.name,
      }).toList();

      final body = <String, dynamic>{
        'title': title,
        'nodes': nodes,
      };
      if (description.isNotEmpty) body['description'] = description;
      if (trafficTotal != null) body['traffic_total'] = trafficTotal;
      if (trafficExpire != null) body['traffic_expire'] = trafficExpire;

      final resp = await http.post(
        Uri.parse('$kApiBase/v1/config/create'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      final code = (jsonDecode(resp.body) as Map)['code'] as String;

      setState(() {
        _code = code;
        _link = '$kApiBase/sub/$code';
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
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
    final state = AppStateScope.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      physics: const BouncingScrollPhysics(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        // ── Готовый код ──
        if (_code != null) ...[
          _CodeCard(code: _code!, link: _link!, onCopyCode: () => _copy(_code!), onCopyLink: () => _copy(_link!)),
          const SizedBox(height: 12),
          Text(
            'Эту ссылку можно вставить в Hiddify, v2rayNG, Streisand и другие клиенты.',
            style: t.textStyles.footnote.copyWith(color: c.textTertiary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          IosButton(
            label: 'Создать ещё одну',
            style: IosButtonStyle.secondary,
            leadingIcon: CupertinoIcons.refresh,
            onPressed: () => setState(() { _code = null; _link = null; }),
          ),
        ] else ...[

          // ── Панель «выбрать/снять все» по всем группам сразу ──
          if (state.groups.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
              child: Row(children: [
                Expanded(child: Text(
                  'Выбрано: $_totalSelected',
                  style: t.textStyles.footnote.copyWith(color: c.textSecondary, letterSpacing: 0.5),
                )),
                _BulkSelectChip(
                  label: 'Выбрать все',
                  icon: CupertinoIcons.checkmark_square,
                  onTap: () => _selectAll(state),
                ),
                const SizedBox(width: 8),
                _BulkSelectChip(
                  label: 'Снять все',
                  icon: CupertinoIcons.square,
                  // Нечего снимать — гасим, чтобы не сбивать с толку.
                  onTap: _totalSelected == 0 ? null : _deselectAll,
                ),
              ]),
            ),

          // ── Серверы из всех групп ──
          if (state.groups.isEmpty)
            const IosListSection(
              header: 'Серверы',
              children: [IosListTile(title: 'Нет добавленных серверов')],
            )
          else
            ...state.groups.map((g) {
              final groupIds = _selected[g.id] ?? {};
              final allSelected = groupIds.length == g.nodes.length && g.nodes.isNotEmpty;
              final expanded = _expandedGroups.contains(g.id);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Заголовок-аккордеон: тап разворачивает/сворачивает группу
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() {
                      if (expanded) {
                        _expandedGroups.remove(g.id);
                      } else {
                        _expandedGroups.add(g.id);
                      }
                    }),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 6),
                      child: Row(children: [
                        Icon(expanded ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_right,
                            size: 14, color: c.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          '${g.title.toUpperCase()} (${groupIds.length} ИЗ ${g.nodes.length})',
                          style: t.textStyles.footnote.copyWith(color: c.textSecondary, letterSpacing: -0.08),
                          overflow: TextOverflow.ellipsis,
                        )),
                      ]),
                    ),
                  ),
                  IosListSection(
                    children: [
                      // Выбрать все / снять
                      IosListTile(
                        title: allSelected ? 'Снять выделение' : 'Выбрать все',
                        leadingIcon: allSelected
                            ? CupertinoIcons.checkmark_square
                            : CupertinoIcons.square,
                        leadingIconBg: c.fill,
                        onTap: () => _toggleGroup(g),
                      ),
                      // Серверы (только если группа развёрнута)
                      if (expanded) ...g.nodes.map((n) {
                        final sel = groupIds.contains(n.id);
                        final displayName = _customNames[n.id] ?? n.name;
                        final isRenamed = _customNames.containsKey(n.id);
                        return Container(
                          constraints: const BoxConstraints(minHeight: 52),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(children: [
                            // Карандаш
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _showRenameNodeDialog(context, n),
                              child: Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: c.fill,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(CupertinoIcons.pencil, size: 17, color: c.textPrimary),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _toggleNode(g.id, n.id),
                                child: Row(children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(displayName, style: t.textStyles.body.copyWith(color: c.textPrimary)),
                                        Text(
                                          isRenamed
                                              ? '✏️ ${n.name} · ${n.protocolLabel} · ${n.address}'
                                              : '${n.protocolLabel} · ${n.address}',
                                          style: t.textStyles.footnote.copyWith(color: c.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 22, height: 22,
                                    decoration: BoxDecoration(
                                      color: sel ? c.textPrimary : Colors.transparent,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: sel ? c.textPrimary : c.textTertiary, width: 1.5),
                                    ),
                                    child: sel ? Icon(CupertinoIcons.check_mark, size: 13, color: c.bgSecondary) : null,
                                  ),
                                ]),
                              ),
                            ),
                          ]),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              );
            }),

          // ── Название ──
          IosListSection(
            header: 'Информация',
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: IosField(
                  controller: _titleCtrl,
                  label: 'Название подписки',
                  placeholder: 'Например: Мои серверы',
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: IosField(
                  controller: _descCtrl,
                  label: 'Описание (необязательно)',
                  placeholder: 'Для друзей, серверы в Европе...',
                  maxLines: 3,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Лимиты ──
          IosListSection(
            header: 'Лимиты (необязательно)',
            footer: 'Лимиты отображаются в VPN-клиентах, поддерживающих subscription-userinfo.',
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: IosField(
                  controller: _trafficCtrl,
                  label: 'Лимит трафика (ГБ)',
                  placeholder: 'Например: 100',
                  keyboardType: TextInputType.number,
                ),
              ),
              IosListTile(
                title: _expireDate != null
                    ? 'Истекает: ${_expireDate!.day}.${_expireDate!.month.toString().padLeft(2, '0')}.${_expireDate!.year}'
                    : 'Срок действия',
                subtitle: _expireDate == null ? 'Нет ограничения' : null,
                leadingIcon: CupertinoIcons.calendar,
                leadingIconBg: c.fill,
                showChevron: true,
                onTap: _pickExpireDate,
              ),
              if (_expireDate != null)
                IosListTile(
                  title: 'Убрать срок',
                  leadingIcon: CupertinoIcons.clear,
                  leadingIconBg: c.fill,
                  onTap: () => setState(() => _expireDate = null),
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
                borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
              ),
              child: Row(children: [
                Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 18, color: c.red),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: t.textStyles.subheadline.copyWith(color: c.red))),
              ]),
            ),

          IosButton(
            label: 'Создать подписку ($_totalSelected серверов)',
            style: IosButtonStyle.primary,
            leadingIcon: CupertinoIcons.share,
            loading: _loading,
            onPressed: _loading ? null : _create,
          ),

          const SizedBox(height: 12),
          Text(
            'Выберите серверы из любых подписок. Получатель сможет ввести код или вставить ссылку в TeleOpen, Hiddify, v2rayNG и другие клиенты.',
            style: t.textStyles.footnote.copyWith(color: c.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ]),
    );
  }
}

// ── Чип «выбрать все / снять все» ──────────────────────────────────────────

class _BulkSelectChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap; // null = выключен
  const _BulkSelectChip({required this.label, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: c.fill,
            borderRadius: BorderRadius.circular(IosShapes.radiusPill),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: c.textPrimary),
            const SizedBox(width: 5),
            Text(label, style: t.textStyles.footnote.copyWith(
              color: c.textPrimary, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

// ── Карточка с готовым кодом (используется CREATE и MTProto вкладками) ──────

class _CodeCard extends StatelessWidget {
  final String code;
  final String link;
  final VoidCallback onCopyCode;
  final VoidCallback onCopyLink;
  const _CodeCard({required this.code, required this.link, required this.onCopyCode, required this.onCopyLink});

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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: c.fill,
              borderRadius: IosShapes.continuous(IosShapes.radiusLarge),
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
          style: t.textStyles.caption1.copyWith(color: c.textTertiary)),

        const SizedBox(height: 20),
        Container(height: 0.5, color: c.separator),
        const SizedBox(height: 16),

        // Ссылка
        Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: c.fill,
                borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
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
              width: 40, height: 40,
              decoration: BoxDecoration(color: c.fill, shape: BoxShape.circle),
              child: Icon(CupertinoIcons.doc_on_clipboard, size: 18, color: c.textPrimary),
            ),
          ),
        ]),
      ]),
    );
  }
}

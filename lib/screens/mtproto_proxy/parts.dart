// lib/screens/mtproto_proxy/parts.dart
//
// Вспомогательные виджеты экрана mtproto_proxy_screen (вынесены из монолита).
part of '../mtproto_proxy_screen.dart';

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

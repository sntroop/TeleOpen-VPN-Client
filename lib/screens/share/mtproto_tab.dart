// lib/screens/share/mtproto_tab.dart
// Вкладка MTProto: ввод/вставка прокси и установка в Telegram, плюс режим
// «Поделиться группой» (генерация 6-значного кода). part of share_screen.

part of '../share_screen.dart';

// ══════════════════════════════════════════════════════════════════════════
// TAB 3: MTProto Proxy для Telegram
//
// MTProto Proxy не подключается VPN-движком приложения — он устанавливается
// внутрь Telegram. Юзер вводит server/port/secret (или вставляет готовую
// ссылку tg://proxy / t.me/proxy), жмёт «Установить» — открывается шит
// выбора форка, и выбранный Telegram показывает штатное окно подключения.
// ══════════════════════════════════════════════════════════════════════════

class _MtProtoTab extends StatefulWidget {
  /// Если передана — вкладка стартует в режиме «Поделиться группой».
  final MtProtoProxyGroup? initialGroup;
  const _MtProtoTab({this.initialGroup});

  @override
  State<_MtProtoTab> createState() => _MtProtoTabState();
}

class _MtProtoTabState extends State<_MtProtoTab> {
  final _serverCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();
  final _shareTitleCtrl = TextEditingController();

  // 0 = ввод полей, 1 = вставка готовой ссылки
  int _mode = 0;
  String? _error;

  // ── Режим «Поделиться группой» ───────────────────────────────────────────
  // Активен, если в таб передали готовую группу. Показываем список прокси
  // с галочками (как у серверов в _CreateTab) и даём создать код/ссылку.
  MtProtoProxyGroup? _shareGroup;
  Set<int> _selectedIdx = {}; // индексы выбранных прокси в группе

  // Состояние генерации кода для MTProto-группы
  bool _shareLoading = false;
  String? _shareCode;
  String? _shareLink;

  bool get _isShareMode => _shareGroup != null;

  @override
  void initState() {
    super.initState();
    final g = widget.initialGroup;
    if (g != null) {
      _shareGroup = g;
      _shareTitleCtrl.text = g.title;
      // По умолчанию выбраны все валидные прокси.
      _selectedIdx = {
        for (var i = 0; i < g.proxies.length; i++)
          if (g.proxies[i].isValid) i
      };
    }
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _portCtrl.dispose();
    _secretCtrl.dispose();
    _linkCtrl.dispose();
    _shareTitleCtrl.dispose();
    super.dispose();
  }

  void _toggleIdx(int i) {
    setState(() {
      if (_selectedIdx.contains(i)) {
        _selectedIdx.remove(i);
      } else {
        _selectedIdx.add(i);
      }
    });
  }

  /// Диалог переименования прокси прямо в режиме «Поделиться группой».
  /// MTProto-ссылка не содержит поля имени, поэтому переименование меняет
  /// сам прокси в группе (proxy.name) и сохраняется — как карандаш у серверов.
  void _showRenameProxyDialog(BuildContext context, MtProtoProxy proxy) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final ctrl = TextEditingController(text: proxy.name);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgSecondary,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        title: Text('Переименовать', style: t.textStyles.headline),
        content: IosField(
          controller: ctrl,
          label: 'Новое название',
          placeholder: proxy.displayName,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Отмена',
                style:
                    t.textStyles.body.copyWith(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final newName = ctrl.text.trim();
              final updated = proxy.copyWith(name: newName);
              final g = _shareGroup;
              if (g != null) {
                final idx = g.proxies.indexOf(proxy);
                if (idx >= 0) {
                  g.proxies[idx] = updated;
                  AppStateScope.of(context, listen: false)
                      .persistMtProtoGroups();
                }
              }
              Navigator.of(ctx).pop();
              if (mounted) setState(() {});
            },
            child: Text('Сохранить',
                style: t.textStyles.body.copyWith(color: c.textPrimary)),
          ),
        ],
      ),
    );
  }

  /// Создаёт 6-значный код для выбранных MTProto-прокси через /v1/mtproto/create.
  Future<void> _createMtProtoCode() async {
    final g = _shareGroup;
    if (g == null) return;

    final title = _shareTitleCtrl.text.trim().isEmpty ? g.title : _shareTitleCtrl.text.trim();

    setState(() { _shareLoading = true; _error = null; _shareCode = null; _shareLink = null; });
    try {
      final selected = <Map<String, String>>[];
      for (var i = 0; i < g.proxies.length; i++) {
        if (!_selectedIdx.contains(i)) continue;
        final p = g.proxies[i];
        if (!p.isValid) continue;
        selected.add({
          'link': p.buildLink(https: true),
          'displayName': p.displayName,
        });
      }
      if (selected.isEmpty) throw Exception('Выберите хотя бы один прокси');

      final resp = await http.post(
        Uri.parse('$kApiBase/v1/mtproto/create'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'title': title, 'proxies': selected}),
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      final code = (jsonDecode(resp.body) as Map)['code'] as String;

      setState(() {
        _shareCode = code;
        _shareLink = '$kApiBase/v1/mtproto/$code';
        _shareLoading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _shareLoading = false; });
    }
  }

  /// Собирает MtProtoProxy из текущего ввода. null + _error если невалидно.
  MtProtoProxy? _buildProxy() {
    if (_mode == 1) {
      final proxy = MtProtoProxy.tryParse(_linkCtrl.text);
      if (proxy == null) {
        _error = 'Не удалось разобрать ссылку. Поддерживаются tg://proxy и '
            'https://t.me/proxy';
      }
      return proxy;
    }

    final server = _serverCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim());
    final secret = _secretCtrl.text.trim();

    if (server.isEmpty) {
      _error = 'Укажите адрес сервера';
      return null;
    }
    if (port == null || port <= 0 || port > 65535) {
      _error = 'Некорректный порт';
      return null;
    }
    if (secret.isEmpty) {
      _error = 'Укажите secret';
      return null;
    }

    final proxy = MtProtoProxy.mtproto(
      server: server,
      port: port,
      secret: secret,
    );
    if (!proxy.isValid) {
      _error = 'Secret выглядит некорректно. Это должна быть hex-строка '
          '(обычно 32 символа) либо fake-TLS secret.';
      return null;
    }
    return proxy;
  }

  Future<void> _install() async {
    setState(() => _error = null);
    final proxy = _buildProxy();
    if (proxy == null) {
      setState(() {});
      return;
    }
    // Шит сам показывает выбор форка и запускает deep-link.
    await showInstallMtProtoProxySheet(context, proxy);
  }

  void _save() {
    setState(() => _error = null);
    final proxy = _buildProxy();
    if (proxy == null) {
      setState(() {});
      return;
    }
    AppStateScope.of(context, listen: false).addMtProtoProxy(proxy);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Прокси сохранён в «Мои прокси»'),
      duration: Duration(seconds: 2),
    ));
  }

  void _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;

    // Пытаемся распознать вставленное: ссылка → разложим по полям.
    final proxy = MtProtoProxy.tryParse(text);
    if (proxy != null && proxy.kind == TelegramProxyKind.mtproto) {
      setState(() {
        _mode = 0;
        _serverCtrl.text = proxy.server;
        _portCtrl.text = proxy.port.toString();
        _secretCtrl.text = proxy.secret;
        _linkCtrl.text = text;
        _error = null;
      });
    } else {
      // Не ссылка — кладём как есть в поле ссылки.
      setState(() {
        _mode = 1;
        _linkCtrl.text = text;
      });
    }
  }

  // ── UI режима «Поделиться группой» ───────────────────────────────────────
  Widget _buildShareGroup(IosThemeData t, IosColors c) {
    final g = _shareGroup!;
    final validCount = g.proxies.where((p) => p.isValid).length;

    // Если код уже создан — показываем результат (как в _CreateTab)
    if (_shareCode != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        physics: const BouncingScrollPhysics(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _CodeCard(
            code: _shareCode!,
            link: _shareLink!,
            onCopyCode: () {
              Clipboard.setData(ClipboardData(text: _shareCode!));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Скопировано'), duration: Duration(seconds: 1)));
            },
            onCopyLink: () {
              Clipboard.setData(ClipboardData(text: _shareLink!));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Скопировано'), duration: Duration(seconds: 1)));
            },
          ),
          const SizedBox(height: 16),
          IosButton(
            label: 'Создать ещё один',
            style: IosButtonStyle.secondary,
            leadingIcon: CupertinoIcons.refresh,
            onPressed: () => setState(() { _shareCode = null; _shareLink = null; }),
          ),
        ]),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      physics: const BouncingScrollPhysics(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        // Заголовок группы
        IosListSection(
          header: 'Группа прокси',
          children: [
            IosListTile(
              title: g.title,
              subtitle: '$validCount прокси',
              trailing: Icon(CupertinoIcons.check_mark,
                  size: 18, color: c.textPrimary),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Список прокси с чекбоксами
        IosListSection(
          header: 'Прокси (${_selectedIdx.length} из ${g.proxies.length})',
          children: [
            // Выбрать все / снять всё
            IosListTile(
              title: _selectedIdx.length == g.proxies.length
                  ? 'Снять выделение'
                  : 'Выбрать все',
              leadingIcon: _selectedIdx.length == g.proxies.length
                  ? CupertinoIcons.checkmark_square
                  : CupertinoIcons.square,
              leadingIconBg: c.fill,
              onTap: () => setState(() {
                if (_selectedIdx.length == g.proxies.length) {
                  _selectedIdx.clear();
                } else {
                  _selectedIdx = {
                    for (var i = 0; i < g.proxies.length; i++) i
                  };
                }
              }),
            ),
            for (var i = 0; i < g.proxies.length; i++)
              _buildProxyRow(t, c, g.proxies[i], i),
          ],
        ),

        const SizedBox(height: 12),

        // Название для получателя
        IosListSection(
          header: 'Название для получателя',
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: IosField(
                controller: _shareTitleCtrl,
                label: 'Название',
                placeholder: 'Например: Мои прокси',
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
              borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
            ),
            child: Row(children: [
              Icon(CupertinoIcons.exclamationmark_triangle_fill,
                  size: 18, color: c.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_error!,
                    style: t.textStyles.subheadline.copyWith(color: c.red)),
              ),
            ]),
          ),

        IosButton(
          label: 'Создать код',
          style: IosButtonStyle.primary,
          leadingIcon: CupertinoIcons.share,
          loading: _shareLoading,
          onPressed: _shareLoading ? null : _createMtProtoCode,
        ),

        const SizedBox(height: 8),

        IosButton(
          label: 'Добавить прокси вручную',
          style: IosButtonStyle.secondary,
          leadingIcon: CupertinoIcons.add,
          onPressed: () => setState(() {
            _shareGroup = null;
            _error = null;
          }),
        ),

        const SizedBox(height: 12),
        Text(
          'Получатель сможет ввести 6-значный код или открыть ссылку в TeleOpen — и получит копию твоих прокси.',
          style: t.textStyles.footnote.copyWith(color: c.textTertiary),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }

  Widget _buildProxyRow(
      IosThemeData t, IosColors c, MtProtoProxy p, int i) {
    final sel = _selectedIdx.contains(i);
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        // Карандаш — отдельная кнопка переименования прокси
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showRenameProxyDialog(context, p),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.fill,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(CupertinoIcons.pencil,
                size: 17, color: c.textPrimary),
          ),
        ),
        const SizedBox(width: 12),
        // Текст + чекбокс — зона выделения прокси
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _toggleIdx(i),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p.displayName,
                        style: t.textStyles.body
                            .copyWith(color: c.textPrimary),
                        overflow: TextOverflow.ellipsis),
                    Text(
                      p.isValid
                          ? '${p.kind.label} · ${p.server}:${p.port}'
                          : '${p.kind.label} · некорректный',
                      style: t.textStyles.footnote.copyWith(
                          color: p.isValid ? c.textSecondary : c.red),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: sel ? c.textPrimary : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: sel ? c.textPrimary : c.textTertiary,
                      width: 1.5),
                ),
                child: sel
                    ? Icon(CupertinoIcons.check_mark,
                        size: 13, color: c.bgSecondary)
                    : null,
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    if (_isShareMode) {
      return _buildShareGroup(t, c);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      physics: const BouncingScrollPhysics(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        // Переключатель режима ввода
        IosSegment(
          activeIndex: _mode,
          onChanged: (i) => setState(() { _mode = i; _error = null; }),
          items: const [
            IosSegmentItem('По полям'),
            IosSegmentItem('Готовая ссылка'),
          ],
        ),
        const SizedBox(height: 16),

        if (_mode == 0) ...[
          IosListSection(
            header: 'Параметры MTProto Proxy',
            footer: 'Secret — это hex-строка (обычно 32 символа). '
                'Поддерживается и fake-TLS secret (начинается с «ee»).',
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: IosField(
                  controller: _serverCtrl,
                  label: 'Сервер',
                  placeholder: 'proxy.example.com  или  1.2.3.4',
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: IosField(
                  controller: _portCtrl,
                  label: 'Порт',
                  placeholder: '443',
                  keyboardType: TextInputType.number,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: IosField(
                  controller: _secretCtrl,
                  label: 'Secret',
                  placeholder: 'ee0123…  или  hex 32 символа',
                ),
              ),
            ],
          ),
        ] else ...[
          IosCard(
            padding: const EdgeInsets.all(12),
            child: IosField(
              controller: _linkCtrl,
              label: 'Ссылка на прокси',
              placeholder: 'tg://proxy?server=…  или  https://t.me/proxy?…',
              maxLines: 3,
            ),
          ),
        ],

        const SizedBox(height: 12),

        IosButton(
          label: 'Вставить из буфера',
          style: IosButtonStyle.secondary,
          leadingIcon: CupertinoIcons.doc_on_clipboard,
          onPressed: _pasteFromClipboard,
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
              Icon(CupertinoIcons.exclamationmark_triangle_fill,
                  size: 18, color: c.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_error!,
                    style: t.textStyles.subheadline.copyWith(color: c.red)),
              ),
            ]),
          ),

        IosButton(
          label: 'Установить в Telegram',
          style: IosButtonStyle.primary,
          leadingIcon: CupertinoIcons.paperplane_fill,
          onPressed: _install,
        ),

        const SizedBox(height: 8),

        IosButton(
          label: 'Сохранить к себе',
          style: IosButtonStyle.secondary,
          leadingIcon: CupertinoIcons.bookmark,
          onPressed: _save,
        ),

        const SizedBox(height: 12),
        Text(
          'Откроется выбор Telegram-клиента (включая форки). После выбора '
          'Telegram сам покажет окно подключения прокси. VPN при этом не '
          'запускается — прокси работает внутри Telegram.',
          style: t.textStyles.footnote.copyWith(color: c.textTertiary),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }
}

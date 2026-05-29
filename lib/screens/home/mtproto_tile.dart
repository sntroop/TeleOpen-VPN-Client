// lib/screens/home/mtproto_tile.dart
// Тайл MTProto-прокси (_MtProtoTile), шит диагностики (_MtProtoDiagnosticsSheet)
// и виджет статистики (_DiagStat). part of home_screen.

part of '../home_screen.dart';

// ── MTProto Proxy Tile ────────────────────────────────────────────────────────
class _MtProtoTile extends StatefulWidget {
  final MtProtoProxyGroup group;
  final MtProtoProxy proxy;
  final AppState state;

  const _MtProtoTile({
    super.key,
    required this.group,
    required this.proxy,
    required this.state,
  });

  @override
  State<_MtProtoTile> createState() => _MtProtoTileState();
}

class _MtProtoTileState extends State<_MtProtoTile> {
  Color _pingColor(int? ms, IosColors c) {
    if (ms == null) return c.textTertiary;
    if (ms < 100) return c.green;
    if (ms < 250) return c.orange;
    return c.red;
  }

  Future<void> _pingOne() async {
    final ms = await MtProtoProxyPinger.pingOne(widget.proxy);
    if (!mounted) return;
    setState(() => widget.proxy.pingMs = ms);
    widget.state.persistMtProtoGroups();
  }

  void _shareProxy(BuildContext context) {
    final link = widget.proxy.buildLink(https: true);
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ссылка скопирована'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showRenameDialog(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final ctrl = TextEditingController(text: widget.proxy.name);
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
            hintText: widget.proxy.displayName,
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
              final newName = ctrl.text.trim();
              final updated = widget.proxy.copyWith(name: newName);
              final group = widget.state.mtProtoGroups
                  .where((g) => g.id == widget.group.id)
                  .cast<MtProtoProxyGroup?>()
                  .firstOrNull;
              if (group != null) {
                final idx = group.proxies.indexOf(widget.proxy);
                if (idx >= 0) {
                  group.proxies[idx] = updated;
                  widget.state.persistMtProtoGroups();
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

  void _showActions(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final fav = widget.proxy.isFavorite;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        margin: EdgeInsets.fromLTRB(
            8, 0, 8, MediaQuery.of(context).padding.bottom + 8),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: c.bgSecondary,
          borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 6),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: c.textQuaternary,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(children: [
              Text(widget.proxy.displayName,
                  style: t.textStyles.headline,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
          IosListTile(
            leadingIcon: CupertinoIcons.paperplane,
            leadingIconBg: c.fill,
            title: 'Установить в Telegram',
            onTap: () {
              Navigator.of(context).pop();
              showInstallMtProtoProxySheet(context, widget.proxy);
            },
          ),
          Container(
              margin: const EdgeInsets.only(left: 54),
              height: 0.5,
              color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.info_circle,
            leadingIconBg: c.fill,
            title: 'О прокси',
            onTap: () {
              Navigator.of(context).pop();
              _showProxyInfo(context);
            },
          ),
          Container(
              margin: const EdgeInsets.only(left: 54),
              height: 0.5,
              color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.pencil,
            leadingIconBg: c.fill,
            title: 'Переименовать',
            onTap: () {
              Navigator.of(context).pop();
              _showRenameDialog(context);
            },
          ),
          Container(
              margin: const EdgeInsets.only(left: 54),
              height: 0.5,
              color: c.separator),
          IosListTile(
            leadingIcon:
                fav ? CupertinoIcons.star_slash : CupertinoIcons.star_fill,
            leadingIconBg: c.fill,
            title: fav ? 'Убрать из избранного' : 'В избранное',
            onTap: () {
              widget.state.toggleFavoriteMtProto(widget.proxy);
              Navigator.of(context).pop();
              if (mounted) setState(() {});
            },
          ),
          Container(
              margin: const EdgeInsets.only(left: 54),
              height: 0.5,
              color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.wifi,
            leadingIconBg: c.fill,
            title: 'Пингануть',
            onTap: () {
              Navigator.of(context).pop();
              _pingOne();
            },
          ),
          Container(
              margin: const EdgeInsets.only(left: 54),
              height: 0.5,
              color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.waveform_path_ecg,
            leadingIconBg: c.fill,
            title: 'Диагностика',
            onTap: () {
              Navigator.of(context).pop();
              _showDiagnostics(context);
            },
          ),
          Container(
              margin: const EdgeInsets.only(left: 54),
              height: 0.5,
              color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.share,
            leadingIconBg: c.fill,
            title: 'Поделиться группой',
            onTap: () {
              Navigator.of(context).pop();
              _showShareGroupSheet(context);
            },
          ),
          Container(
              margin: const EdgeInsets.only(left: 54),
              height: 0.5,
              color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.link,
            leadingIconBg: c.fill,
            title: 'Поделиться',
            onTap: () {
              Navigator.of(context).pop();
              _shareProxy(context);
            },
          ),
          Container(
              margin: const EdgeInsets.only(left: 54),
              height: 0.5,
              color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.trash,
            leadingIconBg: c.red,
            title: 'Удалить прокси',
            titleColor: c.red,
            onTap: () {
              widget.state.removeMtProtoProxy(widget.group.id, widget.proxy);
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 8),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ── «О прокси» ──────────────────────────────────────────────────────────
  void _showProxyInfo(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final p = widget.proxy;

    final jsonData = <String, dynamic>{
      if (p.name.isNotEmpty) 'name': p.name,
      'type': p.kind.name,
      'server': p.server,
      'port': p.port,
      if (p.kind == TelegramProxyKind.mtproto && p.secret.isNotEmpty)
        'secret': p.secret,
      if (p.kind == TelegramProxyKind.socks5 && p.user.isNotEmpty)
        'user': p.user,
      if (p.kind == TelegramProxyKind.socks5 && p.pass.isNotEmpty)
        'pass': p.pass,
      if (p.pingMs != null) 'ping_ms': p.pingMs,
    };
    const encoder = JsonEncoder.withIndent('  ');
    final jsonText = encoder.convert(jsonData);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollController) => Container(
          margin: EdgeInsets.fromLTRB(
              8, 0, 8, MediaQuery.of(context).padding.bottom + 8),
          decoration: BoxDecoration(
            color: c.bgSecondary,
            borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: c.textQuaternary,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('О прокси', style: t.textStyles.headline),
                        const SizedBox(height: 2),
                        Text(p.kind.label,
                            style: t.textStyles.footnote
                                .copyWith(color: c.textSecondary)),
                      ]),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration:
                        BoxDecoration(color: c.fill, shape: BoxShape.circle),
                    child: Icon(CupertinoIcons.xmark,
                        size: 14, color: c.textSecondary),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  _InfoSection(title: 'Основное', c: c, t: t, rows: [
                    _InfoRow('Название', _stripFlag(p.displayName), c, t),
                    _InfoRow('Тип', p.kind.label, c, t),
                    _InfoRow('Сервер', p.server, c, t),
                    _InfoRow('Порт', '${p.port}', c, t),
                    if (p.pingMs != null)
                      _InfoRow('Пинг', '${p.pingMs} ms', c, t,
                          valueColor: _pingColor(p.pingMs, c)),
                  ]),
                  const SizedBox(height: 12),
                  if (p.kind == TelegramProxyKind.mtproto &&
                      p.secret.isNotEmpty)
                    _InfoSection(title: 'MTProto', c: c, t: t, rows: [
                      _InfoRow('Secret', p.secret, c, t),
                    ]),
                  if (p.kind == TelegramProxyKind.socks5 &&
                      (p.user.isNotEmpty || p.pass.isNotEmpty))
                    _InfoSection(title: 'SOCKS5', c: c, t: t, rows: [
                      if (p.user.isNotEmpty) _InfoRow('Логин', p.user, c, t),
                      if (p.pass.isNotEmpty) _InfoRow('Пароль', p.pass, c, t),
                    ]),
                  const SizedBox(height: 12),
                  Text('Json данные',
                      style: t.textStyles.subheadline.copyWith(
                          color: c.blue, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.bgPrimary,
                      borderRadius:
                          IosShapes.continuous(IosShapes.radiusMedium),
                    ),
                    child: SelectableText(
                      jsonText,
                      style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 11.5,
                        color: c.textSecondary,
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  IosButton(
                    label: 'Копировать ссылку',
                    style: IosButtonStyle.secondary,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(
                          text: widget.proxy.buildLink(https: true)));
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Ссылка скопирована'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── «Диагностика» ───────────────────────────────────────────────────────
  // У MTProto-прокси нет нашего xray-хендшейка, поэтому полноценный
  // DiagnosticsScreen (он завязан на VpnNode) не подходит. Делаем серию
  // TCP-замеров до server:port — это показывает доступность и стабильность.
  void _showDiagnostics(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MtProtoDiagnosticsSheet(proxy: widget.proxy),
    );
  }

  // ── «Поделиться группой» ────────────────────────────────────────────────
  // Ведёт на тот же экран ShareScreen, что и у групп серверов — вкладка
  // MTProto открывается в режиме «Поделиться группой» (галочки + копирование).
  void _showShareGroupSheet(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ShareScreen(initialMtProtoGroup: widget.group),
    ));
  }

  String _flag(String name) {
    final runes = name.runes.toList();
    if (runes.isEmpty) return '🌐';
    if (runes.length >= 2 &&
        runes[0] >= 0x1F1E6 && runes[0] <= 0x1F1FF &&
        runes[1] >= 0x1F1E6 && runes[1] <= 0x1F1FF) {
      return String.fromCharCodes([runes[0], runes[1]]);
    }
    return '🌐';
  }

  String _stripFlag(String name) {
    final flag = _flag(name);
    if (name.startsWith(flag)) return name.substring(flag.length).trim();
    return name;
  }

  /// true, если в начале имени стоит настоящий emoji-флаг страны.
  bool _hasCountryFlag(String name) {
    final runes = name.runes.toList();
    return runes.length >= 2 &&
        runes[0] >= 0x1F1E6 &&
        runes[0] <= 0x1F1FF &&
        runes[1] >= 0x1F1E6 &&
        runes[1] <= 0x1F1FF;
  }

  /// Иконка MTProto-тайла: если в имени есть флаг страны — показываем его,
  /// иначе вместо заглушки-глобуса показываем логотип Telegram.
  Widget _buildProxyIcon(String displayName) {
    if (_hasCountryFlag(displayName)) {
      return Text(_flag(displayName), style: const TextStyle(fontSize: 22));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        'assets/telegram.png',
        width: 28,
        height: 28,
        fit: BoxFit.cover,
        // Если ассет не подключён — не падаем, показываем глобус как раньше.
        errorBuilder: (_, __, ___) =>
            const Text('🌐', style: TextStyle(fontSize: 22)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final pingMs = widget.proxy.pingMs;
    final displayName = widget.proxy.displayName;

    return IosCard(
      onTap: () => showInstallMtProtoProxySheet(context, widget.proxy),
      onLongPress: () => _showActions(context),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      radius: IosShapes.radiusLarge,
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: c.fill,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: _buildProxyIcon(displayName)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_stripFlag(displayName), style: t.textStyles.body, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Row(children: [
              Text(widget.proxy.kind.label,
                  style: t.textStyles.caption2.copyWith(color: c.textTertiary, letterSpacing: 0.5)),
              const SizedBox(width: 6),
              Container(width: 3, height: 3, decoration: BoxDecoration(color: c.textTertiary, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              if (pingMs != null)
                Text(
                  '$pingMs ms',
                  style: t.textStyles.caption1.copyWith(color: _pingColor(pingMs, c)),
                ),
            ]),
          ]),
        ),
        // Кнопка пинга (wifi)
        _TileButton(
          icon: CupertinoIcons.wifi,
          onTap: _pingOne,
          color: c.textTertiary,
        ),
        // Звёздочка «избранное» — теперь работает (MtProtoProxy.isFavorite)
        _TileButton(
          icon: widget.proxy.isFavorite
              ? CupertinoIcons.star_fill
              : CupertinoIcons.star,
          onTap: () {
            widget.state.toggleFavoriteMtProto(widget.proxy);
            if (mounted) setState(() {});
          },
          color: widget.proxy.isFavorite ? c.yellow : c.textTertiary,
        ),
        const SizedBox(width: 2),
        // Стрелка вправо
        _TileButton(
          icon: CupertinoIcons.chevron_right,
          onTap: () => _showActions(context),
          color: c.textTertiary,
          size: 14,
        ),
      ]),
    );
  }
}

// ── Диагностика MTProto-прокси ────────────────────────────────────────────────
//
// MTProto-прокси не поднимается xray-движком приложения (он устанавливается
// внутрь Telegram), поэтому полноценная диагностика VPN-узла к нему неприменима.
// Здесь мы делаем серию TCP-замеров до server:port: это объективно показывает
// доступность прокси, среднюю задержку и стабильность соединения.
class _MtProtoDiagnosticsSheet extends StatefulWidget {
  final MtProtoProxy proxy;
  const _MtProtoDiagnosticsSheet({required this.proxy});

  @override
  State<_MtProtoDiagnosticsSheet> createState() =>
      _MtProtoDiagnosticsSheetState();
}

class _MtProtoDiagnosticsSheetState extends State<_MtProtoDiagnosticsSheet> {
  static const int _attempts = 8;

  bool _running = false;
  bool _done = false;
  final List<int?> _results = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _done = false;
      _results.clear();
    });
    for (var i = 0; i < _attempts; i++) {
      final ms = await TcpPing.ping(widget.proxy.server, widget.proxy.port);
      if (!mounted) return;
      setState(() => _results.add(ms));
    }
    // Записываем последний удачный замер как актуальный пинг прокси.
    final lastOk = _results.lastWhere((e) => e != null, orElse: () => null);
    if (lastOk != null) widget.proxy.pingMs = lastOk;
    if (!mounted) return;
    setState(() {
      _running = false;
      _done = true;
    });
  }

  int get _okCount => _results.where((e) => e != null).length;

  int? get _avg {
    final ok = _results.whereType<int>().toList();
    if (ok.isEmpty) return null;
    return (ok.reduce((a, b) => a + b) / ok.length).round();
  }

  int? get _best {
    final ok = _results.whereType<int>().toList();
    if (ok.isEmpty) return null;
    return ok.reduce((a, b) => a < b ? a : b);
  }

  int? get _worst {
    final ok = _results.whereType<int>().toList();
    if (ok.isEmpty) return null;
    return ok.reduce((a, b) => a > b ? a : b);
  }

  Color _verdictColor(IosColors c) {
    if (_results.isEmpty) return c.textTertiary;
    final loss = _attempts - _okCount;
    if (_okCount == 0) return c.red;
    if (loss > 0 || (_avg ?? 9999) > 400) return c.orange;
    return c.green;
  }

  String _verdictText() {
    if (!_done) return 'Идёт проверка…';
    if (_okCount == 0) return 'Прокси недоступен';
    final loss = _attempts - _okCount;
    if (loss > 0) return 'Доступен, но есть потери пакетов';
    if ((_avg ?? 0) > 400) return 'Доступен, но задержка высокая';
    return 'Прокси доступен и стабилен';
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final p = widget.proxy;

    return Container(
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
          width: 36,
          height: 4,
          decoration: BoxDecoration(
              color: c.textQuaternary,
              borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Диагностика', style: t.textStyles.headline),
                    const SizedBox(height: 2),
                    Text('${p.server}:${p.port}',
                        style: t.textStyles.footnote
                            .copyWith(color: c.textSecondary),
                        overflow: TextOverflow.ellipsis),
                  ]),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 28,
                height: 28,
                decoration:
                    BoxDecoration(color: c.fill, shape: BoxShape.circle),
                child: Icon(CupertinoIcons.xmark,
                    size: 14, color: c.textSecondary),
              ),
            ),
          ]),
        ),
        // Вердикт
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _verdictColor(c).withValues(alpha: 0.12),
              borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
            ),
            child: Row(children: [
              if (_running)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CupertinoActivityIndicator(),
                )
              else
                Icon(
                  _okCount == 0
                      ? CupertinoIcons.xmark_circle_fill
                      : (_attempts - _okCount > 0
                          ? CupertinoIcons.exclamationmark_triangle_fill
                          : CupertinoIcons.checkmark_circle_fill),
                  size: 18,
                  color: _verdictColor(c),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_verdictText(),
                    style: t.textStyles.subheadline
                        .copyWith(color: _verdictColor(c))),
              ),
            ]),
          ),
        ),
        // Сводка
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(children: [
            _DiagStat(
                label: 'Успешно',
                value: '$_okCount/$_attempts',
                c: c,
                t: t),
            _DiagStat(
                label: 'Средний',
                value: _avg != null ? '$_avg ms' : '—',
                c: c,
                t: t),
            _DiagStat(
                label: 'Лучший',
                value: _best != null ? '$_best ms' : '—',
                c: c,
                t: t),
            _DiagStat(
                label: 'Худший',
                value: _worst != null ? '$_worst ms' : '—',
                c: c,
                t: t),
          ]),
        ),
        // Лог замеров
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.bgPrimary,
              borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < _results.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Text('Замер ${i + 1}',
                            style: t.textStyles.footnote
                                .copyWith(color: c.textSecondary)),
                        const Spacer(),
                        Text(
                          _results[i] != null
                              ? '${_results[i]} ms'
                              : 'таймаут',
                          style: t.textStyles.footnote.copyWith(
                            color: _results[i] != null
                                ? (_results[i]! < 100
                                    ? c.green
                                    : _results[i]! < 250
                                        ? c.orange
                                        : c.red)
                                : c.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ]),
                    ),
                  if (_running)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CupertinoActivityIndicator(),
                        ),
                        const SizedBox(width: 8),
                        Text('Замер ${_results.length + 1}…',
                            style: t.textStyles.footnote
                                .copyWith(color: c.textTertiary)),
                      ]),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: IosButton(
            label: _running ? 'Проверка…' : 'Повторить',
            style: IosButtonStyle.secondary,
            leadingIcon: CupertinoIcons.arrow_clockwise,
            loading: _running,
            onPressed: _running ? null : _run,
          ),
        ),
      ]),
    );
  }
}

class _DiagStat extends StatelessWidget {
  final String label;
  final String value;
  final IosColors c;
  final IosThemeData t;
  const _DiagStat({
    required this.label,
    required this.value,
    required this.c,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: c.bgPrimary,
          borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
        ),
        child: Column(children: [
          Text(value,
              style: t.textStyles.subheadline
                  .copyWith(fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label,
              style: t.textStyles.caption2.copyWith(color: c.textTertiary)),
        ]),
      ),
    );
  }
}

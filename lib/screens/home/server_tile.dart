// lib/screens/home/server_tile.dart
// Тайл VPN-сервера: tap = выбрать/подключить, long-press = меню, свайпы =
// быстрые действия, шиты «О сервере»/«Переименовать». part of home_screen.

part of '../home_screen.dart';

/// Тайл сервера. Tap = выбрать/подключить. Long-press = меню (Удалить).
class _ServerTile extends StatefulWidget {
  final VpnNode node;
  final AppState state;
  const _ServerTile({super.key, required this.node, required this.state});

  @override
  State<_ServerTile> createState() => _ServerTileState();
}

class _ServerTileState extends State<_ServerTile> with SingleTickerProviderStateMixin {
  late final AnimationController _swipeCtrl;
  double _dragExtent = 0;
  bool _dragActivated = false;
  static const double _actionWidth = 72;
  static const double _deadZone = 20;  // минимальный свайп чтобы начать сдвиг
  static const double _rightThreshold = _actionWidth * 2;
  static const double _leftThreshold = _actionWidth;

  VpnNode get node => widget.node;
  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _swipeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _swipeCtrl.addListener(() {
      if (_swipeCtrl.isAnimating) setState(() {});
    });
  }

  @override
  void dispose() {
    _swipeCtrl.dispose();
    super.dispose();
  }

  void _onHorizontalDragStart(DragStartDetails d) {
    _dragActivated = false;
    _dragStartX = d.localPosition.dx;
  }

  double _dragStartX = 0;

  void _onHorizontalDragUpdate(DragUpdateDetails d) {
    final totalDelta = (d.localPosition.dx - _dragStartX).abs();
    if (!_dragActivated) {
      if (totalDelta < _deadZone) return;
      _dragActivated = true;
    }
    setState(() {
      _dragExtent += d.primaryDelta!;
      _dragExtent = _dragExtent.clamp(-_rightThreshold - 20, _leftThreshold + 20);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails d) {
    if (!_dragActivated) {
      _dragActivated = false;
      return;
    }
    _dragActivated = false;

    double target = 0;
    if (_dragExtent < -_rightThreshold * 0.4) {
      target = -_rightThreshold;
    } else if (_dragExtent > _leftThreshold * 0.4) {
      target = _leftThreshold;
    }
    final start = _dragExtent;
    final tween = Tween<double>(begin: start, end: target);
    _swipeCtrl.reset();
    _swipeCtrl.addListener(() {
      _dragExtent = tween.evaluate(CurvedAnimation(parent: _swipeCtrl, curve: Curves.easeOutCubic));
    });
    _swipeCtrl.forward();
  }

  void _resetSwipe() {
    final start = _dragExtent;
    final tween = Tween<double>(begin: start, end: 0.0);
    _swipeCtrl.reset();
    _swipeCtrl.addListener(() {
      _dragExtent = tween.evaluate(CurvedAnimation(parent: _swipeCtrl, curve: Curves.easeOutCubic));
    });
    _swipeCtrl.forward();
  }

  // ВНИМАНИЕ: НЕ переопределяй здесь operator == и hashCode.
  // Раньше тут было сравнение по node.pingMs / node.isFavorite, но т.к. VpnNode
  // мутируется на месте (новый виджет ссылается на тот же объект), сравнение
  // всегда давало true → Flutter скипал rebuild → визуально звёздочка и пинг
  // не обновлялись, хотя данные менялись. Без кастомного == всё работает само.

  Color _pingColor(int? ms, IosColors c) {
    if (ms == null) return c.textTertiary;
    if (ms < 100) return c.green;
    if (ms < 250) return c.orange;
    return c.red;
  }

  void _showActions(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        margin: EdgeInsets.fromLTRB(8, 0, 8, MediaQuery.of(context).padding.bottom + 8),
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
            width: 36, height: 4,
            decoration: BoxDecoration(color: c.textQuaternary, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(children: [
              Text(node.name, style: t.textStyles.headline, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
          IosListTile(
            leadingIcon: CupertinoIcons.info_circle,
            leadingIconBg: c.fill,
            title: 'О сервере',
            onTap: () {
              Navigator.of(context).pop();
              _showServerInfo(context);
            },
          ),
          Container(margin: const EdgeInsets.only(left: 54), height: 0.5, color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.pencil,
            leadingIconBg: c.fill,
            title: 'Переименовать',
            onTap: () {
              Navigator.of(context).pop();
              _showRenameDialog(context, state, node);
            },
          ),
          Container(margin: const EdgeInsets.only(left: 54), height: 0.5, color: c.separator),
          IosListTile(
            leadingIcon: node.isFavorite ? CupertinoIcons.star_slash : CupertinoIcons.star_fill,
            leadingIconBg: c.fill,
            title: node.isFavorite ? 'Убрать из избранного' : 'В избранное',
            onTap: () { state.toggleFavorite(node); Navigator.of(context).pop(); },
          ),
          Container(margin: const EdgeInsets.only(left: 54), height: 0.5, color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.wifi,
            leadingIconBg: c.fill,
            title: 'Пингануть',
            onTap: () { state.pingOne(node); Navigator.of(context).pop(); },
          ),
          Container(margin: const EdgeInsets.only(left: 54), height: 0.5, color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.waveform_path_ecg,
            leadingIconBg: c.fill,
            title: 'Диагностика',
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DiagnosticsScreen(initialNode: node),
              ));
            },
          ),
          Container(margin: const EdgeInsets.only(left: 54), height: 0.5, color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.rocket_fill,
            leadingIconBg: c.fill,
            title: 'Тест скорости',
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(CupertinoPageRoute(
                builder: (_) => SpeedTestScreen(node: node),
              ));
            },
          ),
          Container(margin: const EdgeInsets.only(left: 54), height: 0.5, color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.share,
            leadingIconBg: c.fill,
            title: 'Создать подписку',
            onTap: () {
              Navigator.of(context).pop();
              final g = AppStateScope.of(context, listen: false).groups
                  .where((gr) => gr.id == node.groupId).cast<VpnGroup?>().firstOrNull;
              if (g != null) {
                Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ShareScreen(group: g),
              ));
              }
            },
          ),
          // Жалоба на сервер — только для нод из market-подписки. Сам факт,
          // что сервер в списке = «добавил себе»; запуск проверяем отдельно.
          if ((node.groupId ?? '').startsWith('market_')) ...[
            Container(margin: const EdgeInsets.only(left: 54), height: 0.5, color: c.separator),
            IosListTile(
              leadingIcon: CupertinoIcons.exclamationmark_bubble,
              leadingIconBg: c.orange,
              title: 'Пожаловаться на сервер',
              onTap: () {
                Navigator.of(context).pop();
                _reportNode();
              },
            ),
          ],
          Container(margin: const EdgeInsets.only(left: 54), height: 0.5, color: c.separator),
          IosListTile(
            leadingIcon: CupertinoIcons.trash,
            leadingIconBg: c.red,
            title: 'Удалить сервер',
            titleColor: c.red,
            onTap: () {
              state.removeNode(node);
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

  // Жалоба на конкретный market-сервер. Доступна, только если пользователь
  // запускал этот сервер (LaunchedNodes) — иначе подсказываем, что нужно
  // сначала подключиться. Это отсекает фейковые репорты.
  Future<void> _reportNode() async {
    final gid = node.groupId ?? '';
    final marketId = int.tryParse(gid.replaceFirst('market_', ''));
    if (marketId == null) return;

    if (!LaunchedNodes.isLaunched(state.prefs, node.reportUriHash)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Сначала запустите этот сервер — жаловаться можно только '
            'на сервер, которым вы пользовались.'),
      ));
      return;
    }

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dctx) => CupertinoAlertDialog(
        title: const Text('Пожаловаться на сервер?'),
        content: Text('«${node.name}» будет отмечен как нерабочий. Если на сервер '
            'пожалуется несколько человек, он скроется у всех.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('Пожаловаться'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await MarketApi.reportNode(groupId: marketId, nodeUriHash: node.reportUriHash);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Жалоба отправлена. Спасибо!'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Не удалось отправить жалобу. Попробуйте позже.'),
      ));
    }
  }

  void _showServerInfo(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    // Парсим JSON из rawUri/params для отображения как в Happ
    final network = node.params['type'] ?? node.params['network'] ?? 'tcp';
    final security = node.params['security'] ?? (node.protocol == VpnProtocol.trojan ? 'tls' : 'none');
    final sni = node.params['sni'] ?? node.params['peer'] ?? node.address;
    final fp = node.params['fp'] ?? node.params['fingerprint'] ?? '';
    final flow = node.params['flow'] ?? '';
    final alpn = node.params['alpn'] ?? '';
    final pbk = node.params['pbk'] ?? '';
    final sid = node.params['sid'] ?? '';

    // Формируем JSON данные сервера как в Happ
    const excludedKeys = ['type', 'network', 'security', 'sni', 'peer',
                           'fp', 'fingerprint', 'flow', 'alpn', 'pbk',
                           'sid', 'inbound_port'];
    final extraParams = Map<String, dynamic>.fromEntries(
      node.params.entries.where((e) => !excludedKeys.contains(e.key)),
    );
    final jsonData = <String, dynamic>{
      'name': node.name,
      'address': node.address,
      'port': node.port,
      'protocol': node.protocolLabel,
      if (network.isNotEmpty && network != 'tcp') 'network': network,
      if (security.isNotEmpty && security != 'none') 'security': security,
      if (sni.isNotEmpty && sni != node.address) 'sni': sni,
      if (fp.isNotEmpty) 'fingerprint': fp,
      if (flow.isNotEmpty) 'flow': flow,
      if (alpn.isNotEmpty) 'alpn': alpn,
      if (pbk.isNotEmpty) 'publicKey': pbk,
      if (sid.isNotEmpty) 'shortId': sid,
      ...extraParams,
    };

    const encoder = JsonEncoder.withIndent('  ');
    final jsonText = encoder.convert(jsonData);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollController) => Container(
          margin: EdgeInsets.fromLTRB(8, 0, 8, MediaQuery.of(context).padding.bottom + 8),
          decoration: BoxDecoration(
            color: c.bgSecondary,
            borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 6),
              width: 36, height: 4,
              decoration: BoxDecoration(color: c.textQuaternary, borderRadius: BorderRadius.circular(2)),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('О сервере', style: t.textStyles.headline),
                    const SizedBox(height: 2),
                    Text(
                      node.protocolLabel,
                      style: t.textStyles.footnote.copyWith(color: c.textSecondary),
                    ),
                  ]),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(color: c.fill, shape: BoxShape.circle),
                    child: Icon(CupertinoIcons.xmark, size: 14, color: c.textSecondary),
                  ),
                ),
              ]),
            ),
            // Info rows
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  // Основная информация
                  _InfoSection(title: 'Основное', c: c, t: t, rows: [
                    _InfoRow('Название', _stripFlag(node.name), c, t),
                    _InfoRow('Адрес', node.address, c, t),
                    _InfoRow('Порт', '${node.port}', c, t),
                    _InfoRow('Протокол', node.protocolLabel, c, t),
                    if (node.pingMs != null)
                      _InfoRow('Пинг', '${node.pingMs} ms', c, t,
                          valueColor: node.pingMs! < 100 ? c.green : node.pingMs! < 250 ? c.orange : c.red),
                  ]),
                  const SizedBox(height: 12),
                  // Настройки подключения
                  if (network.isNotEmpty || security.isNotEmpty || sni.isNotEmpty || fp.isNotEmpty)
                    _InfoSection(title: 'Подключение', c: c, t: t, rows: [
                      if (network.isNotEmpty) _InfoRow('Network', network, c, t),
                      if (security.isNotEmpty && security != 'none') _InfoRow('Security', security, c, t),
                      if (sni.isNotEmpty && sni != node.address) _InfoRow('SNI', sni, c, t),
                      if (fp.isNotEmpty) _InfoRow('Fingerprint', fp, c, t),
                      if (flow.isNotEmpty) _InfoRow('Flow', flow, c, t),
                      if (alpn.isNotEmpty) _InfoRow('ALPN', alpn, c, t),
                      if (pbk.isNotEmpty) _InfoRow('Public Key', pbk, c, t),
                      if (sid.isNotEmpty) _InfoRow('Short ID', sid, c, t),
                    ]),
                  const SizedBox(height: 12),
                  // JSON данные как в Happ
                  Text(
                    'Json данные',
                    style: t.textStyles.subheadline.copyWith(
                      color: c.blue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.bgPrimary,
                      borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
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
                  // Кнопка копировать URI
                  IosButton(
                    label: 'Копировать URI',
                    style: IosButtonStyle.secondary,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: node.rawUri));
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('URI скопирован'),
                        duration: Duration(seconds: 2),
                      ));
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

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final isActive = state.activeNode?.id == node.id;
    final isConnected = isActive && state.status == VpnStatus.connected;

    // Swipe action кнопка
    Widget actionBtn({required IconData icon, required String label, required Color bg, required VoidCallback onTap}) {
      return GestureDetector(
        onTap: () { _resetSwipe(); onTap(); },
        child: Container(
          alignment: Alignment.center,
          color: bg,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
    }

    final card = IosCard(
        onTap: () { _resetSwipe(); state.setActiveOnly(node); },
        onLongPress: () => _showActions(context),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        radius: IosShapes.radiusLarge,
        border: isActive
            ? Border.all(
                color: isConnected ? c.green : c.blue,
                width: 1.5,
              )
            : null,
        backgroundColor: isActive
            ? (isConnected
                ? c.green.withValues(alpha: 0.07)
                : c.blue.withValues(alpha: 0.07))
            : null,
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: isConnected ? c.green.withValues(alpha: 0.15) : c.fill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: Text(_flag(node.name), style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_stripFlag(node.name), style: t.textStyles.body, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Row(children: [
                Text(node.protocolLabel,
                    style: t.textStyles.caption2.copyWith(color: c.textTertiary, letterSpacing: 0.5)),
                const SizedBox(width: 6),
                Container(width: 3, height: 3, decoration: BoxDecoration(color: c.textTertiary, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                if (node.pingMs != null)
                  Text(
                    '${node.pingMs} ms',
                    style: t.textStyles.caption1.copyWith(color: _pingColor(node.pingMs, c)),
                  ),
                // MED-4: предупреждаем, что у ноды отключена проверка TLS.
                if (node.hasInsecureTls) ...[
                  const SizedBox(width: 6),
                  Icon(CupertinoIcons.exclamationmark_shield_fill,
                      size: 13, color: c.orange),
                  const SizedBox(width: 2),
                  Text('TLS без проверки',
                      style: t.textStyles.caption2.copyWith(color: c.orange)),
                ],
              ]),
            ]),
          ),
          // Кнопка быстрого пинга (спидометр)
          _TileButton(
            icon: CupertinoIcons.wifi,
            onTap: () => state.pingOne(node),
            color: c.textTertiary,
          ),
          // Звёздочка
          _TileButton(
            icon: node.isFavorite ? CupertinoIcons.star_fill : CupertinoIcons.star,
            onTap: () => state.toggleFavorite(node),
            color: node.isFavorite ? c.yellow : c.textTertiary,
          ),
          const SizedBox(width: 2),
          // Стрелочка / зелёная точка
          if (isConnected)
            Container(width: 8, height: 8, decoration: BoxDecoration(color: c.green, shape: BoxShape.circle))
          else
            _TileButton(
              icon: CupertinoIcons.chevron_right,
              onTap: () => _showActions(context),
              color: c.textTertiary,
              size: 14,
            ),
        ]),
    );

    return GestureDetector(
      onHorizontalDragStart: _onHorizontalDragStart,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      child: ClipRRect(
        borderRadius: IosShapes.continuous(IosShapes.radiusLarge),
        child: IntrinsicHeight(
          child: Stack(children: [
            // ─── Правая сторона (свайп влево → видны справа) ───
            if (_dragExtent < -16)
            Positioned(
              top: 0, bottom: 0, right: 0,
              width: _rightThreshold,
              child: Row(children: [
                Expanded(child: actionBtn(
                  icon: CupertinoIcons.share,
                  label: 'Поделиться',
                  bg: c.blue,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: node.rawUri));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('URI скопирован'),
                      duration: Duration(seconds: 2),
                    ));
                  },
                )),
                Expanded(child: actionBtn(
                  icon: CupertinoIcons.trash_fill,
                  label: 'Удалить',
                  bg: c.red,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    state.removeNode(node);
                  },
                )),
              ]),
            ),
            // ─── Левая сторона (свайп вправо → видна слева) ───
            if (_dragExtent > 16)
            Positioned(
              top: 0, bottom: 0, left: 0,
              width: _leftThreshold,
              child: actionBtn(
                icon: CupertinoIcons.bolt_fill,
                label: 'Коннект',
                bg: c.green,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  state.setActiveOnly(node);
                  state.connect(node);
                },
              ),
            ),
            // ─── Карточка со сдвигом ───
            Transform.translate(
              offset: Offset(_dragExtent, 0),
              child: card,
            ),
          ]),
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, AppState state, VpnNode node) {
    final ctrl = TextEditingController(text: node.name);
    final t = IosTheme.of(context);
    final c = t.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          margin: EdgeInsets.fromLTRB(8, 0, 8, MediaQuery.of(context).padding.bottom + 8),
          decoration: BoxDecoration(
            color: c.bgSecondary,
            borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 6),
              width: 36, height: 4,
              decoration: BoxDecoration(color: c.textQuaternary, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text('Переименовать', style: t.textStyles.headline),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: IosField(
                controller: ctrl,
                label: 'Новое название',
                placeholder: node.name,
                autofocus: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(children: [
                Expanded(child: IosButton(
                  label: 'Отмена',
                  style: IosButtonStyle.secondary,
                  onPressed: () => Navigator.of(context).pop(),
                )),
                const SizedBox(width: 10),
                Expanded(child: IosButton(
                  label: 'Сохранить',
                  style: IosButtonStyle.primary,
                  onPressed: () {
                    final newName = ctrl.text.trim();
                    if (newName.isNotEmpty) state.renameNode(node, newName);
                    Navigator.of(context).pop();
                  },
                )),
              ]),
            ),
          ]),
        ),
      ),
    );
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
}

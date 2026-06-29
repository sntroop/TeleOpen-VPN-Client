// lib/screens/byedpi_screen.dart
//
// Экран «Обход DPI (ByeDPI)» — приёмы десинхронизации в стиле ByeByeDPI:
//   - Прокси: макс. подключений, размер буфера, «Без домена», TCP Fast Open
//   - Десинхронизация: режим хостов, TTL, метод, позиция разделения, SACK
//   - Протоколы: десинхронизация HTTP / HTTPS / UDP
//   - HTTP: смешанный регистр хоста/домена, удаление пробелов
//   - HTTPS: разбивка TLS-записи, позиция, разбивка по SNI
//   - UDP: количество поддельных UDP
//
// ВАЖНО: значения сохраняются в AppSettings (prefs + toCoreConfig → bdpi_*),
// но реальную десинхронизацию пакетов выполняет НАТИВНЫЙ движок ByeDPI,
// которого в текущей сборке ещё нет — трафик идёт через ядро xray/mihomo,
// эти приёмы не применяющее. Это такой же UI-слой, как «Трюки TLS».

import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ios_theme.dart';
import '../main.dart';

class ByeDpiScreen extends StatefulWidget {
  const ByeDpiScreen({super.key});

  @override
  State<ByeDpiScreen> createState() => _ByeDpiScreenState();
}

class _ByeDpiScreenState extends State<ByeDpiScreen> {
  late AppSettings _s;

  @override
  void initState() {
    super.initState();
    _s = AppSettings.copy(AppStateScope.of(context, listen: false).settings);
  }

  void _update(void Function(AppSettings s) mutate) {
    setState(() => mutate(_s));
    AppStateScope.of(context, listen: false).updateSettings(_s);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ── Стратегия (ручной ввод аргументов) ──────────────────────────────────

  void _editStrategy() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _StrategyEditSheet(
        initial: _s.bdpiStrategy,
        onSave: (v) => _update((s) => s.bdpiStrategy = v.trim()),
      ),
    );
  }

  // ── Импорт / экспорт ────────────────────────────────────────────────────

  Future<void> _exportSettings() async {
    final json = const JsonEncoder.withIndent('  ').convert(_s.byeDpiToJson());
    await Clipboard.setData(ClipboardData(text: json));
    _toast('Настройки обхода DPI скопированы');
  }

  Future<void> _importSettings() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text?.trim() ?? '';
    if (raw.isEmpty) {
      _toast('Буфер обмена пуст');
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('Ожидается JSON-объект');
      _update((s) => s.applyByeDpiJson(decoded.cast<String, dynamic>()));
      _toast('Настройки импортированы');
    } catch (e) {
      _toast('Не удалось импортировать: ${e is FormatException ? e.message : 'неверный формат'}');
    }
  }

  String _shortStrategy(String s) {
    final t = s.trim();
    if (t.isEmpty) return 'Не задано';
    return t.length > 64 ? '${t.substring(0, 64)}…' : t;
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: _ScreenHeader(title: 'Обход DPI')),

            // ── Режим ───────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Режим',
                footer:
                    'Когда включено, кнопка «Подключить» поднимает обход DPI '
                    'напрямую (через ciadpi, без VPN-сервера) — именно в этом '
                    'режиме приёмы десинхронизации ниже реально применяются. '
                    'Выключено — работает обычное подключение к серверу.',
                children: [
                  _switchRow(
                    icon: CupertinoIcons.shield_lefthalf_fill,
                    title: 'Использовать обход DPI',
                    value: _s.bdpiModeEnabled,
                    onChanged: (v) => _update((s) => s.bdpiModeEnabled = v),
                  ),
                ],
              ),
            ),

            // ── Своя стратегия ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Своя стратегия',
                footer:
                    'Вставьте сюда строку аргументов ciadpi (например найденную '
                    'в Telegram). Пока поле непустое, она применяется как есть, '
                    'минуя тумблеры. Пусто — работают тумблеры ниже.',
                children: [
                  IosListTile(
                    leadingIcon: CupertinoIcons.text_cursor,
                    leadingIconBg: IosTheme.of(context).colors.fill,
                    title: 'Аргументы ciadpi',
                    subtitle: _shortStrategy(_s.bdpiStrategy),
                    showChevron: true,
                    onTap: _editStrategy,
                  ),
                ],
              ),
            ),

            // ── Прокси ──────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Прокси',
                footer:
                    'Приёмы десинхронизации применяются нативным движком ByeDPI. '
                    'Пока он не подключён, значения сохраняются, но трафик идёт '
                    'через ядро без обхода.',
                children: [
                  _numberRow(
                    icon: CupertinoIcons.arrow_2_squarepath,
                    title: 'Максимум подключений',
                    value: _s.bdpiMaxConnections,
                    placeholder: '512',
                    onSelect: (v) => _update((s) => s.bdpiMaxConnections = v),
                  ),
                  _numberRow(
                    icon: CupertinoIcons.square_stack_3d_up,
                    title: 'Размер буфера',
                    value: _s.bdpiBufferSize,
                    placeholder: '16384',
                    onSelect: (v) => _update((s) => s.bdpiBufferSize = v),
                  ),
                  _switchRow(
                    icon: CupertinoIcons.globe,
                    title: 'Без домена',
                    value: _s.bdpiNoDomain,
                    onChanged: (v) => _update((s) => s.bdpiNoDomain = v),
                  ),
                  _switchRow(
                    icon: CupertinoIcons.bolt_horizontal,
                    title: 'TCP Fast Open',
                    value: _s.bdpiTcpFastOpen,
                    onChanged: (v) => _update((s) => s.bdpiTcpFastOpen = v),
                  ),
                ],
              ),
            ),

            // ── Десинхронизация ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Десинхронизация',
                children: [
                  _optionsRow(
                    icon: CupertinoIcons.list_bullet,
                    title: 'Хосты',
                    value: _s.bdpiHostsMode,
                    options: kBdpiHostsModes,
                    onSelect: (v) => _update((s) => s.bdpiHostsMode = v),
                  ),
                  _numberRow(
                    icon: CupertinoIcons.number,
                    title: 'TTL по умолчанию',
                    value: _s.bdpiDefaultTtl,
                    placeholder: '8',
                    onSelect: (v) => _update((s) => s.bdpiDefaultTtl = v),
                  ),
                  _optionsRow(
                    icon: CupertinoIcons.scissors_alt,
                    title: 'Метод десинхронизации',
                    value: _s.bdpiDesyncMethod,
                    options: kBdpiDesyncMethods,
                    onSelect: (v) => _update((s) => s.bdpiDesyncMethod = v),
                  ),
                  _numberRow(
                    icon: CupertinoIcons.arrow_left_right,
                    title: 'Позиция разделения',
                    value: _s.bdpiSplitPosition,
                    placeholder: '1',
                    onSelect: (v) => _update((s) => s.bdpiSplitPosition = v),
                  ),
                  _switchRow(
                    icon: CupertinoIcons.placemark,
                    title: 'Разделить в хосте',
                    value: _s.bdpiSplitAtHost,
                    onChanged: (v) => _update((s) => s.bdpiSplitAtHost = v),
                  ),
                  _switchRow(
                    icon: CupertinoIcons.trash,
                    title: 'Отбрасывать SACK',
                    value: _s.bdpiDropSack,
                    onChanged: (v) => _update((s) => s.bdpiDropSack = v),
                  ),
                ],
              ),
            ),

            // ── Протоколы ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Протоколы',
                children: [
                  _switchRow(
                    icon: CupertinoIcons.globe,
                    title: 'Десинхронизация HTTP',
                    value: _s.bdpiDesyncHttp,
                    onChanged: (v) => _update((s) => s.bdpiDesyncHttp = v),
                  ),
                  _switchRow(
                    icon: CupertinoIcons.lock_shield,
                    title: 'Десинхронизация HTTPS',
                    value: _s.bdpiDesyncHttps,
                    onChanged: (v) => _update((s) => s.bdpiDesyncHttps = v),
                  ),
                  _switchRow(
                    icon: CupertinoIcons.antenna_radiowaves_left_right,
                    title: 'Десинхронизация UDP',
                    value: _s.bdpiDesyncUdp,
                    onChanged: (v) => _update((s) => s.bdpiDesyncUdp = v),
                  ),
                ],
              ),
            ),

            // ── HTTP ────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'HTTP',
                children: [
                  _switchRow(
                    icon: CupertinoIcons.textformat,
                    title: 'Смешанный регистр хоста',
                    value: _s.bdpiHostMixedCase,
                    onChanged: (v) => _update((s) => s.bdpiHostMixedCase = v),
                  ),
                  _switchRow(
                    icon: CupertinoIcons.textformat_alt,
                    title: 'Смешанный регистр домена',
                    value: _s.bdpiDomainMixedCase,
                    onChanged: (v) => _update((s) => s.bdpiDomainMixedCase = v),
                  ),
                  _switchRow(
                    icon: CupertinoIcons.delete_left,
                    title: 'Удалить пробелы из хоста',
                    value: _s.bdpiHostRemoveSpaces,
                    onChanged: (v) => _update((s) => s.bdpiHostRemoveSpaces = v),
                  ),
                ],
              ),
            ),

            // ── HTTPS ───────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'HTTPS',
                children: [
                  _switchRow(
                    icon: CupertinoIcons.scissors,
                    title: 'Разделить TLS-запись',
                    value: _s.bdpiTlsRecordSplit,
                    onChanged: (v) => _update((s) => s.bdpiTlsRecordSplit = v),
                  ),
                  _numberRow(
                    icon: CupertinoIcons.arrow_left_right,
                    title: 'Позиция разделения TLS-записи',
                    value: _s.bdpiTlsRecordSplitPos,
                    placeholder: '0',
                    onSelect: (v) => _update((s) => s.bdpiTlsRecordSplitPos = v),
                  ),
                  _switchRow(
                    icon: CupertinoIcons.tag,
                    title: 'Разделить TLS-запись в SNI',
                    value: _s.bdpiTlsRecordSplitAtSni,
                    onChanged: (v) =>
                        _update((s) => s.bdpiTlsRecordSplitAtSni = v),
                  ),
                ],
              ),
            ),

            // ── UDP ─────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'UDP',
                children: [
                  _numberRow(
                    icon: CupertinoIcons.number_circle,
                    title: 'Количество поддельных UDP',
                    value: _s.bdpiFakeUdpCount,
                    placeholder: '0',
                    onSelect: (v) => _update((s) => s.bdpiFakeUdpCount = v),
                  ),
                ],
              ),
            ),

            // ── Импорт / экспорт ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Импорт / экспорт',
                footer:
                    'Экспорт копирует все настройки обхода DPI (включая стратегию) '
                    'в буфер обмена — удобно поделиться. Импорт читает такую же '
                    'строку из буфера и применяет её.',
                children: [
                  IosListTile(
                    leadingIcon: CupertinoIcons.square_arrow_up,
                    leadingIconBg: c.fill,
                    title: 'Экспорт настроек',
                    subtitle: 'Скопировать в буфер обмена',
                    showChevron: true,
                    onTap: _exportSettings,
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.square_arrow_down,
                    leadingIconBg: c.fill,
                    title: 'Импорт настроек',
                    subtitle: 'Вставить из буфера обмена',
                    showChevron: true,
                    onTap: _importSettings,
                  ),
                ],
              ),
            ),

            SliverToBoxAdapter(
              child: SizedBox(height: MediaQuery.of(context).padding.bottom + 32),
            ),
          ],
        ),
      ),
    );
  }

  // ── helpers ────────────────────────────────────────────────────────────

  Widget _switchRow({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final c = IosTheme.of(context).colors;
    return IosListTile(
      leadingIcon: icon,
      leadingIconBg: c.fill,
      title: title,
      trailing: IosSwitch(value: value, onChanged: onChanged),
    );
  }

  Widget _optionsRow({
    required IconData icon,
    required String title,
    required String value,
    required List<String> options,
    required ValueChanged<String> onSelect,
  }) {
    final c = IosTheme.of(context).colors;
    return IosListTile(
      leadingIcon: icon,
      leadingIconBg: c.fill,
      title: title,
      subtitle: value,
      showChevron: true,
      onTap: () => _showOptions(
        title: title,
        options: options,
        current: value,
        onSelect: onSelect,
      ),
    );
  }

  Widget _numberRow({
    required IconData icon,
    required String title,
    required String value,
    required String placeholder,
    required ValueChanged<String> onSelect,
  }) {
    final c = IosTheme.of(context).colors;
    return IosListTile(
      leadingIcon: icon,
      leadingIconBg: c.fill,
      title: title,
      trailingText: value,
      showChevron: true,
      onTap: () => _showNumberInput(
        title: title,
        placeholder: placeholder,
        current: value,
        onSelect: onSelect,
      ),
    );
  }

  void _showOptions({
    required String title,
    required List<String> options,
    required String current,
    required ValueChanged<String> onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _OptionsSheet(
        title: title,
        options: options,
        currentValue: current,
        onSelect: onSelect,
      ),
    );
  }

  void _showNumberInput({
    required String title,
    required String placeholder,
    required String current,
    required ValueChanged<String> onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _NumberInputSheet(
        title: title,
        placeholder: placeholder,
        currentValue: current,
        onSelect: onSelect,
      ),
    );
  }
}

// ─── Header ─────────────────────────────────────────────────────────────────

class _ScreenHeader extends StatelessWidget {
  final String title;
  const _ScreenHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
      child: Row(
        children: [
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
          const SizedBox(width: 4),
          Text(title, style: t.textStyles.title3),
          const Spacer(),
        ],
      ),
    );
  }
}

// ─── Sheets ─────────────────────────────────────────────────────────────────

class _OptionsSheet extends StatelessWidget {
  final String title;
  final List<String> options;
  final String currentValue;
  final ValueChanged<String> onSelect;

  const _OptionsSheet({
    required this.title,
    required this.options,
    required this.currentValue,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    final tiles = <Widget>[];
    for (int i = 0; i < options.length; i++) {
      final v = options[i];
      final selected = v == currentValue;
      tiles.add(IosListTile(
        title: v,
        trailing: selected
            ? Icon(CupertinoIcons.check_mark, size: 18, color: c.textPrimary)
            : null,
        onTap: () {
          onSelect(v);
          Navigator.of(context).pop();
        },
      ));
      if (i < options.length - 1) {
        tiles.add(Container(margin: const EdgeInsets.only(left: 16), height: 0.5, color: c.separator));
      }
    }

    return Container(
      margin: EdgeInsets.fromLTRB(8, 0, 8, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: c.bgSecondary,
        borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 6),
            width: 36, height: 4,
            decoration: BoxDecoration(color: c.textQuaternary, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(children: [
              Text(title, style: t.textStyles.headline),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Icon(CupertinoIcons.xmark_circle_fill, size: 28, color: c.textQuaternary),
              ),
            ]),
          ),
          ...tiles,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _NumberInputSheet extends StatefulWidget {
  final String title;
  final String placeholder;
  final String currentValue;
  final ValueChanged<String> onSelect;

  const _NumberInputSheet({
    required this.title,
    required this.placeholder,
    required this.currentValue,
    required this.onSelect,
  });

  @override
  State<_NumberInputSheet> createState() => _NumberInputSheetState();
}

class _NumberInputSheetState extends State<_NumberInputSheet> {
  late final TextEditingController _ctrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentValue);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  String? _validate(String v) {
    final s = v.trim();
    if (s.isEmpty) return 'Введите число';
    if (int.tryParse(s) == null) return 'Ожидается целое число';
    if (int.parse(s) < 0) return 'Число не может быть отрицательным';
    return null;
  }

  void _apply() {
    final value = _ctrl.text.trim();
    final err = _validate(value);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    widget.onSelect(value);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        margin: EdgeInsets.fromLTRB(8, 0, 8, MediaQuery.of(context).padding.bottom + 8),
        decoration: BoxDecoration(
          color: c.bgSecondary,
          borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 6),
              alignment: Alignment.center,
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: c.textQuaternary, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(children: [
                Expanded(child: Text(widget.title, style: t.textStyles.headline)),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(CupertinoIcons.xmark_circle_fill, size: 28, color: c.textQuaternary),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: IosField(
                controller: _ctrl,
                label: 'Значение',
                placeholder: widget.placeholder,
                keyboardType: TextInputType.number,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                _error ?? 'Целое число, например ${widget.placeholder}',
                style: t.textStyles.footnote.copyWith(
                  color: _error != null ? c.red : c.textSecondary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: IosButton(
                label: 'Применить',
                style: IosButtonStyle.primary,
                onPressed: _apply,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─── Strategy editor (многострочный ввод сырых аргументов ciadpi) ───────────

class _StrategyEditSheet extends StatefulWidget {
  final String initial;
  final ValueChanged<String> onSave;

  const _StrategyEditSheet({required this.initial, required this.onSave});

  @override
  State<_StrategyEditSheet> createState() => _StrategyEditSheetState();
}

class _StrategyEditSheetState extends State<_StrategyEditSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.trim().isNotEmpty) {
      _ctrl.text = text.trim();
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    }
  }

  void _save() {
    widget.onSave(_ctrl.text);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        margin: EdgeInsets.fromLTRB(8, 0, 8, MediaQuery.of(context).padding.bottom + 8),
        decoration: BoxDecoration(
          color: c.bgSecondary,
          borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 6),
              alignment: Alignment.center,
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: c.textQuaternary, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(children: [
                Expanded(child: Text('Своя стратегия', style: t.textStyles.headline)),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _paste,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(CupertinoIcons.doc_on_clipboard, size: 22, color: c.blue),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(CupertinoIcons.xmark_circle_fill, size: 28, color: c.textQuaternary),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: IosField(
                controller: _ctrl,
                label: 'Аргументы ciadpi',
                placeholder: '-s1+s -As -d1+s …',
                maxLines: 5,
                autofocus: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Сырая строка аргументов. Иконка-буфер вверху — вставить из '
                'буфера. Очистите поле, чтобы вернуться к тумблерам/пресету.',
                style: t.textStyles.footnote.copyWith(color: c.textSecondary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: IosButton(
                label: 'Сохранить',
                style: IosButtonStyle.primary,
                onPressed: _save,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

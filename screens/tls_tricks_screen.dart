import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ios_theme.dart';

class TlsTricksScreen extends StatefulWidget {
  const TlsTricksScreen({super.key});

  @override
  State<TlsTricksScreen> createState() => _TlsTricksScreenState();
}

class _TlsTricksScreenState extends State<TlsTricksScreen> {
  bool _fragmentationEnabled = false;
  String _fragmentPackets = 'TLS Hello';
  String _fragmentSize = '10-30';
  String _fragmentDelay = '2-8';
  bool _mixedSniCase = false;
  bool _paddingEnabled = false;
  String _paddingSize = '1-1500';

  static const _packetOptions = <String>[
    'TLS Hello',
    'TCP',
    'TLS Hello + TCP',
    'Всё',
  ];

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
            SliverToBoxAdapter(child: _ScreenHeader(title: 'Трюки TLS')),

            
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Фрагментация',
                children: [
                  IosListTile(
                    leadingIcon: CupertinoIcons.scissors,
                    leadingIconBg: c.fill,
                    title: 'Включить фрагментацию',
                    trailing: IosSwitch(
                      value: _fragmentationEnabled,
                      onChanged: (v) => setState(() => _fragmentationEnabled = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.square_stack,
                    leadingIconBg: c.fill,
                    title: 'Пакеты фрагментации',
                    subtitle: _fragmentPackets,
                    showChevron: true,
                    onTap: () => _showOptions(
                      title: 'Пакеты фрагментации',
                      options: _packetOptions,
                      current: _fragmentPackets,
                      onSelect: (v) => setState(() => _fragmentPackets = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.arrow_left_right,
                    leadingIconBg: c.fill,
                    title: 'Размер фрагмента',
                    subtitle: _fragmentSize,
                    showChevron: true,
                    onTap: () => _showRangeInput(
                      title: 'Размер фрагмента',
                      placeholder: '10-30',
                      current: _fragmentSize,
                      onSelect: (v) => setState(() => _fragmentSize = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.alarm,
                    leadingIconBg: c.fill,
                    title: 'Задержка фрагмента',
                    subtitle: _fragmentDelay,
                    showChevron: true,
                    onTap: () => _showRangeInput(
                      title: 'Задержка фрагмента',
                      placeholder: '2-8',
                      current: _fragmentDelay,
                      onSelect: (v) => setState(() => _fragmentDelay = v),
                    ),
                  ),
                ],
              ),
            ),

            
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'SNI',
                children: [
                  IosListTile(
                    leadingIcon: CupertinoIcons.textformat,
                    leadingIconBg: c.fill,
                    title: 'Включить смешанный регистр SNI',
                    trailing: IosSwitch(
                      value: _mixedSniCase,
                      onChanged: (v) => setState(() => _mixedSniCase = v),
                    ),
                  ),
                ],
              ),
            ),

            
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Дополнение',
                children: [
                  IosListTile(
                    leadingIcon: CupertinoIcons.arrow_up_down,
                    leadingIconBg: c.fill,
                    title: 'Включить дополнение',
                    trailing: IosSwitch(
                      value: _paddingEnabled,
                      onChanged: (v) => setState(() => _paddingEnabled = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.arrow_left_right,
                    leadingIconBg: c.fill,
                    title: 'Размер дополнения',
                    subtitle: _paddingSize,
                    showChevron: true,
                    onTap: () => _showRangeInput(
                      title: 'Размер дополнения',
                      placeholder: '1-1500',
                      current: _paddingSize,
                      onSelect: (v) => setState(() => _paddingSize = v),
                    ),
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

  void _showRangeInput({
    required String title,
    required String placeholder,
    required String current,
    required ValueChanged<String> onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RangeInputSheet(
        title: title,
        placeholder: placeholder,
        currentValue: current,
        onSelect: onSelect,
      ),
    );
  }
}

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

class _RangeInputSheet extends StatefulWidget {
  final String title;
  final String placeholder;
  final String currentValue;
  final ValueChanged<String> onSelect;

  const _RangeInputSheet({
    required this.title,
    required this.placeholder,
    required this.currentValue,
    required this.onSelect,
  });

  @override
  State<_RangeInputSheet> createState() => _RangeInputSheetState();
}

class _RangeInputSheetState extends State<_RangeInputSheet> {
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
    final m = RegExp(r'^(\d+)\s*-\s*(\d+)$').firstMatch(s);
    if (m == null) return 'Ожидается формат "число-число"';
    final a = int.parse(m.group(1)!);
    final b = int.parse(m.group(2)!);
    if (a > b) return 'Минимум должен быть не больше максимума';
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
                Text(widget.title, style: t.textStyles.headline),
                const Spacer(),
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
                label: 'Диапазон',
                placeholder: widget.placeholder,
                keyboardType: TextInputType.text,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                _error ?? 'Формат: мин-макс, например ${widget.placeholder}',
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

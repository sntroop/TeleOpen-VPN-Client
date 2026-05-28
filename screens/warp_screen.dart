import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ios_theme.dart';

class WarpScreen extends StatefulWidget {
  const WarpScreen({super.key});

  @override
  State<WarpScreen> createState() => _WarpScreenState();
}

class _WarpScreenState extends State<WarpScreen> {
  bool _enabled = false;
  String _routingMode = 'Направлять WARP через прокси';
  String _licenseKey = '';
  String _cleanIp = 'auto';
  int _port = 0;
  String _noiseCount = '1-3';
  String _noiseMode = 'm4';
  String _noiseSize = '10-30';
  String _noiseDelay = '2-8';

  static const _routingModes = <String>[
    'Направлять WARP через прокси',
    'Направлять прокси через WARP',
    'Только WARP',
  ];

  static const _noiseModes = <String>['m1', 'm2', 'm3', 'm4', 'm5', 'm6'];

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
            SliverToBoxAdapter(child: _ScreenHeader(title: 'WARP')),

            
            SliverToBoxAdapter(
              child: IosListSection(
                children: [
                  IosListTile(
                    leadingIcon: CupertinoIcons.cloud,
                    leadingIconBg: c.blue,
                    title: 'Включить WARP',
                    trailing: IosSwitch(
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.wrench,
                    leadingIconBg: c.fill,
                    title: 'Сгенерировать конфигурацию WARP',
                    showChevron: true,
                    onTap: _generateConfig,
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.arrow_branch,
                    leadingIconBg: c.fill,
                    title: 'Режим маршрутизации WARP',
                    subtitle: _routingMode,
                    showChevron: true,
                    onTap: () => _showOptions(
                      title: 'Режим маршрутизации WARP',
                      options: _routingModes,
                      current: _routingMode,
                      onSelect: (v) => setState(() => _routingMode = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.lock,
                    leadingIconBg: c.fill,
                    title: 'Лицензионный ключ',
                    subtitle: _licenseKey.isEmpty ? 'Не задано' : _maskedLicense(),
                    showChevron: true,
                    onTap: () => _showTextInput(
                      title: 'Лицензионный ключ',
                      placeholder: 'XXXXXXXX-XXXXXXXX-XXXXXXXX',
                      current: _licenseKey,
                      onSelect: (v) => setState(() => _licenseKey = v),
                    ),
                  ),
                ],
              ),
            ),

            
            SliverToBoxAdapter(
              child: IosListSection(
                children: [
                  IosListTile(
                    leadingIcon: CupertinoIcons.sparkles,
                    leadingIconBg: c.fill,
                    title: 'Чистый IP',
                    subtitle: _cleanIp,
                    showChevron: true,
                    onTap: () => _showTextInput(
                      title: 'Чистый IP',
                      placeholder: 'auto или 162.159.x.x',
                      current: _cleanIp,
                      onSelect: (v) => setState(() => _cleanIp = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.share_up,
                    leadingIconBg: c.fill,
                    title: 'Порт',
                    subtitle: _port.toString(),
                    showChevron: true,
                    onTap: () => _showNumberInput(
                      title: 'Порт',
                      placeholder: '0 - авто',
                      current: _port,
                      onSelect: (v) => setState(() => _port = v),
                    ),
                  ),
                ],
              ),
            ),

            
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Шум',
                children: [
                  IosListTile(
                    leadingIcon: CupertinoIcons.square_stack_3d_up,
                    leadingIconBg: c.fill,
                    title: 'Количество шума',
                    subtitle: _noiseCount,
                    showChevron: true,
                    onTap: () => _showRangeInput(
                      title: 'Количество шума',
                      placeholder: '1-3',
                      current: _noiseCount,
                      onSelect: (v) => setState(() => _noiseCount = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.circle_grid_hex,
                    leadingIconBg: c.fill,
                    title: 'Режим шума',
                    subtitle: _noiseMode,
                    showChevron: true,
                    onTap: () => _showOptions(
                      title: 'Режим шума',
                      options: _noiseModes,
                      current: _noiseMode,
                      onSelect: (v) => setState(() => _noiseMode = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.arrow_left_right,
                    leadingIconBg: c.fill,
                    title: 'Размер шума',
                    subtitle: _noiseSize,
                    showChevron: true,
                    onTap: () => _showRangeInput(
                      title: 'Размер шума',
                      placeholder: '10-30',
                      current: _noiseSize,
                      onSelect: (v) => setState(() => _noiseSize = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.timer,
                    leadingIconBg: c.fill,
                    title: 'Задержка шума',
                    subtitle: _noiseDelay,
                    showChevron: true,
                    onTap: () => _showRangeInput(
                      title: 'Задержка шума',
                      placeholder: '2-8',
                      current: _noiseDelay,
                      onSelect: (v) => setState(() => _noiseDelay = v),
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

  String _maskedLicense() {
    if (_licenseKey.length <= 8) return _licenseKey;
    return '${_licenseKey.substring(0, 4)}…${_licenseKey.substring(_licenseKey.length - 4)}';
  }

  void _generateConfig() {
    IosDialog.show(
      context,
      IosDialog(
        title: 'Генерация конфигурации',
        description: 'Будет создана новая конфигурация WARP с регистрацией нового устройства. Продолжить?',
        actions: [
          IosButton(
            label: 'Создать',
            style: IosButtonStyle.primary,
            onPressed: () {
              Navigator.of(context).pop();
              
            },
          ),
          IosButton(
            label: 'Отмена',
            style: IosButtonStyle.plain,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
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

  void _showTextInput({
    required String title,
    required String placeholder,
    required String current,
    required ValueChanged<String> onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SingleFieldSheet(
        title: title,
        placeholder: placeholder,
        currentValue: current,
        keyboardType: TextInputType.text,
        onSelect: onSelect,
      ),
    );
  }

  void _showNumberInput({
    required String title,
    required String placeholder,
    required int current,
    required ValueChanged<int> onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SingleFieldSheet(
        title: title,
        placeholder: placeholder,
        currentValue: current.toString(),
        keyboardType: TextInputType.number,
        onSelect: (v) {
          final n = int.tryParse(v.trim()) ?? current;
          onSelect(n);
        },
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
      builder: (_) => _SingleFieldSheet(
        title: title,
        placeholder: placeholder,
        currentValue: current,
        keyboardType: TextInputType.text,
        helperText: 'Формат: мин-макс, например 10-30',
        validator: _validateRange,
        onSelect: onSelect,
      ),
    );
  }

  static String? _validateRange(String v) {
    final s = v.trim();
    final m = RegExp(r'^(\d+)\s*-\s*(\d+)$').firstMatch(s);
    if (m == null) return 'Ожидается формат "число-число"';
    final a = int.parse(m.group(1)!);
    final b = int.parse(m.group(2)!);
    if (a > b) return 'Минимум должен быть не больше максимума';
    return null;
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

class _SingleFieldSheet extends StatefulWidget {
  final String title;
  final String placeholder;
  final String currentValue;
  final TextInputType keyboardType;
  final String? helperText;
  final String? Function(String)? validator;
  final ValueChanged<String> onSelect;

  const _SingleFieldSheet({
    required this.title,
    required this.placeholder,
    required this.currentValue,
    required this.keyboardType,
    required this.onSelect,
    this.helperText,
    this.validator,
  });

  @override
  State<_SingleFieldSheet> createState() => _SingleFieldSheetState();
}

class _SingleFieldSheetState extends State<_SingleFieldSheet> {
  late final TextEditingController _ctrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentValue);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _apply() {
    final value = _ctrl.text.trim();
    if (widget.validator != null) {
      final err = widget.validator!(value);
      if (err != null) {
        setState(() => _error = err);
        return;
      }
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
                label: 'Значение',
                placeholder: widget.placeholder,
                keyboardType: widget.keyboardType,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
            ),
            if (widget.helperText != null || _error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  _error ?? widget.helperText!,
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

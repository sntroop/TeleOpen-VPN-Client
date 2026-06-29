// lib/screens/settings/parts.dart
//
// Вспомогательные виджеты экрана settings_screen (вынесены из монолита).
part of '../settings_screen.dart';

class _SettingsHeader extends StatelessWidget {
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
          const Spacer(),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// BOTTOM SHEETS
// ════════════════════════════════════════════════════════════════════════════

class _DnsPickerSheet extends StatefulWidget {
  final String currentValue;
  final ValueChanged<String> onSelect;
  const _DnsPickerSheet({required this.currentValue, required this.onSelect});

  @override
  State<_DnsPickerSheet> createState() => _DnsPickerSheetState();
}

class _DnsPickerSheetState extends State<_DnsPickerSheet> {
  late final TextEditingController _ctrl;
  static const _presets = [
    ('1.1.1.1', 'Cloudflare'),
    ('8.8.8.8', 'Google'),
    ('9.9.9.9', 'Quad9'),
    ('1.0.0.1', 'Cloudflare alt'),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentValue);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _apply(String v) {
    final value = v.trim();
    if (value.isEmpty) return;
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
                Text('DNS-сервер', style: t.textStyles.headline),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(CupertinoIcons.xmark_circle_fill, size: 28, color: c.textQuaternary),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: IosField(
                controller: _ctrl,
                label: 'Свой адрес',
                placeholder: 'Например 1.1.1.1',
                keyboardType: TextInputType.text,
                onChanged: (_) {},
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: IosButton(
                label: 'Применить',
                style: IosButtonStyle.primary,
                onPressed: () => _apply(_ctrl.text),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                'ПРЕСЕТЫ',
                style: t.textStyles.footnote.copyWith(color: c.textSecondary, letterSpacing: 0.5),
              ),
            ),
            for (int i = 0; i < _presets.length; i++) ...[
              IosListTile(
                title: _presets[i].$1,
                subtitle: _presets[i].$2,
                trailing: widget.currentValue == _presets[i].$1
                    ? Icon(CupertinoIcons.check_mark, size: 18, color: c.textPrimary)
                    : null,
                onTap: () {
                  _ctrl.text = _presets[i].$1;
                  _apply(_presets[i].$1);
                },
              ),
              if (i < _presets.length - 1)
                Container(margin: const EdgeInsets.only(left: 16), height: 0.5, color: c.separator),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _OptionPickerSheet extends StatelessWidget {
  final String title;
  final List<String> options;
  final String currentValue;
  final ValueChanged<String> onSelect;

  const _OptionPickerSheet({
    required this.title,
    required this.options,
    required this.currentValue,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return _BottomSheetContainer(
      title: title,
      children: options.map((v) {
        final selected = v == currentValue;
        return IosListTile(
          title: v,
          trailing: selected
              ? Icon(CupertinoIcons.check_mark, size: 18, color: c.textPrimary)
              : null,
          onTap: () {
            onSelect(v);
            Navigator.of(context).pop();
          },
        );
      }).toList(),
    );
  }
}

class _BottomSheetContainer extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _BottomSheetContainer({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    final tiles = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      tiles.add(children[i]);
      if (i < children.length - 1) {
        tiles.add(Container(margin: const EdgeInsets.only(left: 54), height: 0.5, color: c.separator));
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

// lib/ios_theme/components/field.dart
// IosField (поле ввода со стилем «Value»/placeholder). part of ios_theme.

part of '../../ios_theme.dart';

// ─── 5.4 IosField (поле ввода в стиле «Value» / placeholder) ────────────────

class IosField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;          // верхний лейбл
  final String? placeholder;
  final ValueChanged<String>? onChanged;
  final TextInputType keyboardType;
  final bool obscureText;
  final int maxLines;
  final bool autofocus;

  const IosField({
    super.key,
    this.controller,
    this.label,
    this.placeholder,
    this.onChanged,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.maxLines = 1,
    this.autofocus = false,
  });

  @override
  State<IosField> createState() => _IosFieldState();
}

class _IosFieldState extends State<IosField> {
  late final FocusNode _focus;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() { _focus.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return AnimatedContainer(
      duration: IosDurations.fast,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.fill,
        borderRadius: IosShapes.continuous(IosShapes.radiusField),
        border: Border.all(
          color: _focused ? c.blue.withValues(alpha: 0.5) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.label != null) ...[
            Text(widget.label!, style: t.textStyles.footnote.copyWith(color: c.textSecondary)),
            const SizedBox(height: 2),
          ],
          TextField(
            controller: widget.controller,
            focusNode: _focus,
            autofocus: widget.autofocus,
            onChanged: widget.onChanged,
            keyboardType: widget.keyboardType,
            obscureText: widget.obscureText,
            maxLines: widget.maxLines,
            cursorColor: c.blue,
            style: t.textStyles.body,
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: widget.placeholder,
              hintStyle: t.textStyles.body.copyWith(color: c.textTertiary),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

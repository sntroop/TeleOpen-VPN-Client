// lib/ios_theme/components/button.dart
// IosButton (primary / destructive / secondary / plain). part of ios_theme.

part of '../../ios_theme.dart';

// ─── 5.1 IosButton (Primary / Destructive / Secondary / Plain) ───────────────

enum IosButtonStyle { primary, destructive, secondary, plain }

class IosButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IosButtonStyle style;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool fullWidth;
  final bool loading;

  const IosButton({
    super.key,
    required this.label,
    this.onPressed,
    this.style = IosButtonStyle.primary,
    this.leadingIcon,
    this.trailingIcon,
    this.fullWidth = true,
    this.loading = false,
  });

  @override
  State<IosButton> createState() => _IosButtonState();
}

class _IosButtonState extends State<IosButton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this, duration: IosDurations.fast, lowerBound: 0, upperBound: 1,
  );
  late final Animation<double> _scale = Tween(begin: 1.0, end: 0.96)
      .animate(CurvedAnimation(parent: _ctrl, curve: IosDurations.easeOut));

  bool get _enabled => widget.onPressed != null && !widget.loading;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    Color bg; Color fg;
    switch (widget.style) {
      case IosButtonStyle.primary:
        bg = c.blue;
        // fg должен контрастировать с bg. В этой палитре c.blue в тёмной теме
        // равен белому, поэтому Colors.white давал белый текст на белом фоне.
        // Считаем contrast по luminance.
        fg = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
            ? Colors.white
            : Colors.black;
        break;
      case IosButtonStyle.destructive:
        bg = c.fill;
        fg = c.red;
        break;
      case IosButtonStyle.secondary:
        bg = c.fill;
        fg = c.textPrimary;
        break;
      case IosButtonStyle.plain:
        bg = Colors.transparent;
        fg = c.blue;
        break;
    }
    if (!_enabled) {
      if (widget.style == IosButtonStyle.primary) {
        bg = c.textPrimary.withValues(alpha: 0.35);
      } else {
        bg = c.fillTertiary;
        fg = fg.withValues(alpha: 0.4);
      }
    }

    final content = Row(
      mainAxisSize: widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          SizedBox(
            width: 18, height: 18,
            child: CupertinoActivityIndicator(color: fg),
          )
        else if (widget.leadingIcon != null) ...[
          Icon(widget.leadingIcon, size: 18, color: fg),
          const SizedBox(width: 8),
        ],
        if (!widget.loading)
          Flexible(
            child: Text(
              widget.label,
              style: t.textStyles.headline.copyWith(color: fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (widget.trailingIcon != null) ...[
          const SizedBox(width: 8),
          Icon(widget.trailingIcon, size: 18, color: fg),
        ],
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _enabled ? (_) => _ctrl.forward() : null,
      onTapUp:   _enabled ? (_) => _ctrl.reverse() : null,
      onTapCancel: _enabled ? () => _ctrl.reverse() : null,
      onTap: _enabled ? widget.onPressed : null,
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: IosDurations.fast,
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: IosShapes.continuous(IosShapes.radiusButton),
          ),
          child: Center(child: content),
        ),
      ),
    );
  }
}

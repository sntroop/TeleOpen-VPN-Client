// lib/ios_theme/components/card.dart
// IosCard (универсальная карточка с тенью). part of ios_theme.

part of '../../ios_theme.dart';

// ─── 5.3 IosCard (универсальная карточка с тенью) ────────────────────────────

class IosCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color? backgroundColor;
  final bool elevated;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Border? border;

  const IosCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.radius = IosShapes.radiusXLarge,
    this.backgroundColor,
    this.elevated = true,
    this.onTap,
    this.onLongPress,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? c.bgSecondary,
        borderRadius: IosShapes.continuous(radius),
        border: border,
        boxShadow: elevated ? IosShadows.card(c) : null,
      ),
      child: child,
    );

    final wrapped = (onTap != null || onLongPress != null)
        ? GestureDetector(
            // deferToChild: тапы на дочерние GestureDetector'ы (кнопки, звёздочки)
            // обрабатываются ими, а тап на пустое место карточки — родителем.
            // С opaque родитель забирал все тапы себе, и кнопки внутри не работали.
            behavior: HitTestBehavior.deferToChild,
            onTap: onTap,
            onLongPress: onLongPress,
            child: box,
          )
        : box;

    return margin != null ? Padding(padding: margin!, child: wrapped) : wrapped;
  }
}

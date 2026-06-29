// lib/ios_theme/components/segment.dart
// IosSegmentItem + IosSegment (pill-сегментед-контрол). part of ios_theme.

part of '../../ios_theme.dart';

// ─── 5.5 IosSegment (pill «Item | Item | Item» с активным красным) ──────────

class IosSegmentItem {
  final String label;
  final IconData? icon;
  final bool destructive;
  const IosSegmentItem(this.label, {this.icon, this.destructive = false});
}

class IosSegment extends StatelessWidget {
  final List<IosSegmentItem> items;
  final int activeIndex;
  final ValueChanged<int> onChanged;
  final bool hasOverflow;
  final VoidCallback? onOverflowTap;

  const IosSegment({
    super.key,
    required this.items,
    required this.activeIndex,
    required this.onChanged,
    this.hasOverflow = false,
    this.onOverflowTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    final children = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      final it = items[i];
      final color = it.destructive ? c.red : c.textPrimary;

      children.add(GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (it.icon != null) ...[
              Icon(it.icon, size: 16, color: color),
              const SizedBox(width: 4),
            ],
            Text(it.label, style: t.textStyles.subheadline.copyWith(color: color)),
          ]),
        ),
      ));

      // разделитель между элементами
      if (i < items.length - 1) {
        children.add(Container(
          width: 1, height: 18,
          margin: const EdgeInsets.symmetric(vertical: 8),
          color: c.separator,
        ));
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: c.bgSecondary,
        borderRadius: BorderRadius.circular(IosShapes.radiusPill),
        boxShadow: IosShadows.card(c),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...children,
          if (hasOverflow)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOverflowTap,
              child: Container(
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.fill,
                  shape: BoxShape.circle,
                ),
                child: Icon(CupertinoIcons.chevron_right, size: 16, color: c.textPrimary),
              ),
            ),
        ],
      ),
    );
  }
}

// lib/ios_theme/components/menu.dart
// IosMenuItem / IosMenuSection / IosMenu (контекстное меню). part of ios_theme.

part of '../../ios_theme.dart';

// ─── 5.6 IosMenuItem / IosMenu (контекстное меню как на скрине Figma) ───────

enum IosMenuItemKind { regular, disabled, destructive }

class IosMenuItem {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? trailing;        // ⌘ A, > , и т.д.
  final IconData? trailingIcon;  // например chevron_right
  final IosMenuItemKind kind;
  final VoidCallback? onTap;

  const IosMenuItem({
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.trailingIcon,
    this.kind = IosMenuItemKind.regular,
    this.onTap,
  });
}

class IosMenuSection {
  final String? title;
  final List<IosMenuItem> items;
  const IosMenuSection({this.title, required this.items});
}

class IosMenu extends StatelessWidget {
  final List<IosMenuSection> sections;
  final double width;

  const IosMenu({super.key, required this.sections, this.width = 250});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    final children = <Widget>[];
    for (int sIdx = 0; sIdx < sections.length; sIdx++) {
      final sec = sections[sIdx];
      if (sec.title != null) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Text(
            sec.title!,
            style: t.textStyles.caption1.copyWith(color: c.textTertiary),
          ),
        ));
      }
      for (int i = 0; i < sec.items.length; i++) {
        children.add(_buildItem(context, sec.items[i]));
        if (i < sec.items.length - 1) {
          children.add(Container(
            margin: const EdgeInsets.only(left: 44),
            height: 0.5, color: c.separator,
          ));
        }
      }
      // separator section
      if (sIdx < sections.length - 1) {
        children.add(Container(height: 8, color: c.bgPrimary.withValues(alpha: 0.5)));
      }
    }

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: c.bgSecondary,
        borderRadius: IosShapes.continuous(IosShapes.radiusLarge),
        boxShadow: IosShadows.elevated(c),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _buildItem(BuildContext context, IosMenuItem it) {
    final t = IosTheme.of(context);
    final c = t.colors;

    Color color;
    switch (it.kind) {
      case IosMenuItemKind.regular:     color = c.textPrimary; break;
      case IosMenuItemKind.disabled:    color = c.textTertiary; break;
      case IosMenuItemKind.destructive: color = c.red; break;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: it.kind == IosMenuItemKind.disabled ? null : it.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            if (it.icon != null) ...[
              Icon(it.icon, size: 18, color: color),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(it.title, style: t.textStyles.body.copyWith(color: color)),
                  if (it.subtitle != null)
                    Text(it.subtitle!, style: t.textStyles.footnote.copyWith(color: c.textTertiary)),
                ],
              ),
            ),
            if (it.trailing != null)
              Text(it.trailing!, style: t.textStyles.subheadline.copyWith(color: c.textTertiary)),
            if (it.trailingIcon != null)
              Icon(it.trailingIcon, size: 14, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}

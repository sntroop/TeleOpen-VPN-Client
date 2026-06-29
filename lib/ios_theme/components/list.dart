// lib/ios_theme/components/list.dart
// IosListSection + IosListTile (секции и строки настроек). part of ios_theme.

part of '../../ios_theme.dart';

// ─── 5.7 IosListSection (секция настроек как Settings.app) ──────────────────

class IosListSection extends StatelessWidget {
  final String? header;
  final String? footer;
  final List<Widget> children;

  /// Необязательный виджет, прижатый к правому краю строки заголовка
  /// (например, кнопка «···» или «Поделиться»). Рисуется только если
  /// задан [header].
  final Widget? headerTrailing;

  const IosListSection({
    super.key,
    this.header,
    this.footer,
    this.headerTrailing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    final tiles = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      tiles.add(children[i]);
      if (i < children.length - 1) {
        tiles.add(Container(
          margin: const EdgeInsets.only(left: 54),
          height: 0.5, color: c.separator,
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null) Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  header!.toUpperCase(),
                  style: t.textStyles.footnote
                      .copyWith(color: c.textSecondary, letterSpacing: -0.08),
                ),
              ),
              if (headerTrailing != null) headerTrailing!,
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: c.bgSecondary,
            borderRadius: IosShapes.continuous(IosShapes.radiusLarge),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: tiles),
        ),
        if (footer != null) Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: Text(
            footer!,
            style: t.textStyles.footnote.copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}

// ─── 5.8 IosListTile (универсальная строка списка) ──────────────────────────

class IosListTile extends StatelessWidget {
  final Widget? leading;
  final IconData? leadingIcon;
  final Color? leadingIconBg;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final String? trailingText;
  final bool showChevron;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? titleColor;

  const IosListTile({
    super.key,
    this.leading,
    this.leadingIcon,
    this.leadingIconBg,
    required this.title,
    this.subtitle,
    this.trailing,
    this.trailingText,
    this.showChevron = false,
    this.onTap,
    this.onLongPress,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    Widget? lead = leading;
    if (lead == null && leadingIcon != null) {
      final bg = leadingIconBg ?? c.fill;
      // Цвет иконки выбираем по яркости подложки, а не по «цветная/нейтральная».
      // Иначе акцент c.blue (в тёмной теме это чисто белый) даёт белую иконку на
      // белом фоне — кнопка выглядит пустым белым квадратом.
      final isNeutral = bg == c.fill || bg == c.fillSecondary || bg == c.fillTertiary;
      lead = Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(
          leadingIcon,
          size: 17,
          color: isNeutral
              ? c.textPrimary
              : (bg.computeLuminance() > 0.6 ? Colors.black : Colors.white),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          if (lead != null) ...[lead, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: t.textStyles.body.copyWith(color: titleColor ?? c.textPrimary)),
                if (subtitle != null)
                  Text(subtitle!, style: t.textStyles.footnote.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
          if (trailingText != null)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(left: 8, right: 4),
                child: Text(
                  trailingText!,
                  style: t.textStyles.body.copyWith(color: c.textSecondary),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
          if (trailing != null) trailing!,
          if (showChevron) Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(CupertinoIcons.chevron_right, size: 14, color: c.textTertiary),
          ),
        ]),
      ),
    );
  }
}

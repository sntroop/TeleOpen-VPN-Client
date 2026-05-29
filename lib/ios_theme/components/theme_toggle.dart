// lib/ios_theme/components/theme_toggle.dart
// IosThemeToggle (готовая кнопка Light/Dark). part of ios_theme.

part of '../../ios_theme.dart';

// ─── 5.10 IosThemeToggle (готовая кнопка-переключатель Light/Dark) ──────────

class IosThemeToggle extends StatelessWidget {
  const IosThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = IosThemeScope.of(context);
    final t = IosTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: scope.toggle,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: t.colors.fill,
          shape: BoxShape.circle,
        ),
        child: Icon(
          scope.isDark ? CupertinoIcons.sun_max_fill : CupertinoIcons.moon_fill,
          size: 18, color: t.colors.textPrimary,
        ),
      ),
    );
  }
}

// lib/ios_theme/components/dialog.dart
// IosDialog (модалка Title + Description + actions). part of ios_theme.

part of '../../ios_theme.dart';

// ─── 5.9 IosDialog (карточка с Title + Description + actions) ───────────────

class IosDialog extends StatelessWidget {
  final String title;
  final String? description;
  final List<Widget> content;
  final List<Widget> actions;

  const IosDialog({
    super.key,
    required this.title,
    this.description,
    this.content = const [],
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: c.bgSecondary,
          borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
          boxShadow: IosShadows.elevated(c),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: t.textStyles.headline.copyWith(fontWeight: FontWeight.w700)),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(description!, style: t.textStyles.body.copyWith(color: c.textSecondary)),
            ],
            if (content.isNotEmpty) ...[
              const SizedBox(height: 18),
              ...content,
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 18),
              ...actions.map((w) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: w,
              )),
            ],
          ],
        ),
      ),
    );
  }

  /// Удобный вызов showDialog
  static Future<T?> show<T>(BuildContext context, IosDialog dialog) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.4),
      transitionDuration: IosDurations.normal,
      pageBuilder: (_, __, ___) => Material(
        // type.transparency — не рисует фон Material, но даёт DefaultTextStyle
        // и убирает жёлтое подчёркивание "free-floating" текста под showGeneralDialog
        type: MaterialType.transparency,
        child: dialog,
      ),
      transitionBuilder: (_, anim, __, child) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween(begin: 0.95, end: 1.0)
                .animate(CurvedAnimation(parent: anim, curve: IosDurations.easeOut)),
            child: child,
          ),
        );
      },
    );
  }
}

// lib/screens/home/info_display.dart
// Общие виджеты для шитов «О сервере»/«О прокси»: секция, строка и кнопка-иконка
// тайла. Используются server_tile и mtproto_tile. part of home_screen.

part of '../home_screen.dart';

// ── Вспомогательные виджеты для экрана "О сервере" ───────────────────────────

class _InfoSection extends StatelessWidget {
  final String title;
  final IosColors c;
  final IosThemeData t;
  final List<Widget> rows;

  const _InfoSection({required this.title, required this.c, required this.t, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        title,
        style: t.textStyles.subheadline.copyWith(
          color: c.blue,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: c.bgPrimary,
          borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: rows),
      ),
    ]);
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IosColors c;
  final IosThemeData t;
  final Color? valueColor;

  const _InfoRow(this.label, this.value, this.c, this.t, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Text(label, style: t.textStyles.footnote.copyWith(color: c.textSecondary)),
        const Spacer(),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            style: t.textStyles.footnote.copyWith(
              color: valueColor ?? c.textPrimary,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}

// ── Кнопка-иконка внутри тайла (корректно работает рядом с onLongPress) ───────
class _TileButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final double size;

  const _TileButton({
    required this.icon,
    required this.onTap,
    required this.color,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // opaque — гарантируем, что тап на эту зону НЕ улетит в родительский
      // GestureDetector карточки (который теперь deferToChild)
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        // увеличена тап-зона, чтобы попадать пальцем по иконке размером 16
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Icon(icon, size: size, color: color),
      ),
    );
  }
}

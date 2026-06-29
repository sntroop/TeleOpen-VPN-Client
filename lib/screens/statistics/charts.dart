// lib/screens/statistics/charts.dart
// Суммарные карточки и недельный bar-chart трафика. part of statistics_screen.

part of '../statistics_screen.dart';

class _SummaryCard extends StatelessWidget {
  final IosThemeData t;
  final IosColors c;
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _SummaryCard({
    required this.t,
    required this.c,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.bgSecondary,
        borderRadius: IosShapes.continuous(IosShapes.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 8),
          Text(value, style: t.textStyles.title2.copyWith(color: c.textPrimary)),
          const SizedBox(height: 2),
          Text(label, style: t.textStyles.caption1.copyWith(color: c.textSecondary)),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  const _LegendDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _DayBar {
  final String label;
  final int rx;
  final int tx;
  const _DayBar({required this.label, required this.rx, required this.tx});
}

class _WeekBarChart extends StatelessWidget {
  final List<_DayBar> bars;
  final int maxBytes;
  final Color rxColor;
  final Color txColor;

  const _WeekBarChart({
    required this.bars,
    required this.maxBytes,
    required this.rxColor,
    required this.txColor,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _BarChartPainter(
        bars: bars,
        maxBytes: maxBytes,
        rxColor: rxColor,
        txColor: txColor,
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<_DayBar> bars;
  final int maxBytes;
  final Color rxColor;
  final Color txColor;

  _BarChartPainter({
    required this.bars,
    required this.maxBytes,
    required this.rxColor,
    required this.txColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty || maxBytes == 0) return;

    const barGap = 4.0;
    final groupWidth = size.width / bars.length;
    final halfBarW = (groupWidth - barGap * 3) / 2;
    final radius = Radius.circular(math.min(halfBarW / 2, 4));

    for (int i = 0; i < bars.length; i++) {
      final bar = bars[i];
      final groupLeft = i * groupWidth + barGap;

      // RX bar (левый)
      final rxH = (bar.rx / maxBytes) * size.height;
      if (rxH > 0) {
        final rxRect = RRect.fromRectAndCorners(
          Rect.fromLTWH(groupLeft, size.height - rxH, halfBarW, rxH),
          topLeft: radius, topRight: radius,
        );
        canvas.drawRRect(rxRect, Paint()..color = rxColor.withValues(alpha: 0.85));
      }

      // TX bar (правый)
      final txH = (bar.tx / maxBytes) * size.height;
      if (txH > 0) {
        final txRect = RRect.fromRectAndCorners(
          Rect.fromLTWH(groupLeft + halfBarW + barGap, size.height - txH, halfBarW, txH),
          topLeft: radius, topRight: radius,
        );
        canvas.drawRRect(txRect, Paint()..color = txColor.withValues(alpha: 0.85));
      }
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter o) =>
      o.bars != bars || o.maxBytes != maxBytes;
}

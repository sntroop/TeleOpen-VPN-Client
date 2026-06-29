// lib/screens/speed_test/parts.dart
//
// Вспомогательные виджеты экрана speed_test_screen (вынесены из монолита).
part of '../speed_test_screen.dart';

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String unit;
  final IosColors colors;
  final IosTextStyles textStyles;

  const _MetricCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.unit,
    required this.colors,
    required this.textStyles,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: IosShapes.continuous(IosShapes.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Text(label,
                style: textStyles.caption1
                    .copyWith(color: colors.textTertiary, letterSpacing: 0.8)),
          ]),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: textStyles.title2.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: [const FontFeature.tabularFigures()],
                  )),
              const SizedBox(width: 4),
              Text(unit,
                  style: textStyles.caption1
                      .copyWith(color: colors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  КАСТОМНЫЙ PAINTER — СПИДОМЕТР (gauge)
// ═════════════════════════════════════════════════════════════════════════════

class _GaugePainter extends CustomPainter {
  final double needleValue; // 0..1
  final SpeedTestPhase phase;
  final double pulseValue;
  final Color arcColor;
  final Color arcBgColor;
  final Color needleColor;
  final Color centerColor;
  final Color tickColor;
  final Color textColor;
  final Color secondaryTextColor;
  final double currentSpeed;
  final int pingMs;
  final Brightness brightness;

  _GaugePainter({
    required this.needleValue,
    required this.phase,
    required this.pulseValue,
    required this.arcColor,
    required this.arcBgColor,
    required this.needleColor,
    required this.centerColor,
    required this.tickColor,
    required this.textColor,
    required this.secondaryTextColor,
    required this.currentSpeed,
    required this.pingMs,
    required this.brightness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.52;
    final radius = math.min(size.width * 0.30, size.height * 0.38);

    // Дуга: от 210° до -30° (всего 240°)
    const startAngle = 210 * math.pi / 180;
    const sweepAngle = 240 * math.pi / 180;

    final center = Offset(cx, cy);

    // ── Фоновая дуга ──
    final bgPaint = Paint()
      ..color = arcBgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      -sweepAngle,
      false,
      bgPaint,
    );

    // ── Цветная дуга (прогресс) ──
    if (needleValue > 0) {
      final arcPaint = Paint()
        ..color = arcColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        -sweepAngle * needleValue.clamp(0, 1),
        false,
        arcPaint,
      );
    }

    // ── Тики и подписи (ВНУТРИ дуги) ──
    final scaleValues = [0, 5, 10, 50, 100, 250, 500];
    for (final val in scaleValues) {
      final frac = val == 0
          ? 0.0
          : (math.log(val + 1) / math.log(501)).clamp(0.0, 1.0);
      final angle = startAngle - sweepAngle * frac;

      // Тик — короткая чёрточка снаружи дуги
      final innerR = radius + 4;
      final outerR = radius + 14;
      final p1 = Offset(
        cx + innerR * math.cos(angle),
        cy + innerR * math.sin(angle),
      );
      final p2 = Offset(
        cx + outerR * math.cos(angle),
        cy + outerR * math.sin(angle),
      );
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = tickColor
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );

      // Подпись — ещё дальше снаружи
      final labelR = radius + 26;
      final labelPos = Offset(
        cx + labelR * math.cos(angle),
        cy + labelR * math.sin(angle),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '$val',
          style: TextStyle(
            color: secondaryTextColor,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(labelPos.dx - tp.width / 2, labelPos.dy - tp.height / 2),
      );
    }

    // ── Стрелка ──
    final needleAngle = startAngle - sweepAngle * needleValue.clamp(0, 1);
    final needleLen = radius - 14;

    final needleTip = Offset(
      cx + needleLen * math.cos(needleAngle),
      cy + needleLen * math.sin(needleAngle),
    );

    // Тень стрелки
    canvas.drawLine(
      center,
      needleTip,
      Paint()
        ..color = arcColor.withValues(alpha: 0.12)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Сама стрелка
    canvas.drawLine(
      center,
      needleTip,
      Paint()
        ..color = needleColor
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    // ── Центральный круг (с пульсацией) ──
    final pulseRadius = 8.0 + (phase != SpeedTestPhase.idle &&
            phase != SpeedTestPhase.done
        ? math.sin(pulseValue * 2 * math.pi) * 2
        : 0);

    canvas.drawCircle(
      center,
      pulseRadius + 3,
      Paint()..color = centerColor.withValues(alpha: 0.15),
    );
    canvas.drawCircle(
      center,
      pulseRadius,
      Paint()..color = centerColor,
    );
    canvas.drawCircle(
      center,
      pulseRadius - 2,
      Paint()
        ..color = brightness == Brightness.dark ? Colors.black : Colors.white,
    );

    // ── Центральная скорость ──
    if (phase == SpeedTestPhase.download || phase == SpeedTestPhase.upload) {
      final speedStr = currentSpeed > 0
          ? currentSpeed.toStringAsFixed(1)
          : '0';
      final speedTp = TextPainter(
        text: TextSpan(
          text: speedStr,
          style: TextStyle(
            color: textColor,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      speedTp.paint(
        canvas,
        Offset(cx - speedTp.width / 2, cy - radius * 0.75),
      );

      final unitTp = TextPainter(
        text: TextSpan(
          text: 'Мбит/с',
          style: TextStyle(
            color: secondaryTextColor,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      unitTp.paint(
        canvas,
        Offset(cx - unitTp.width / 2, cy - radius * 0.38),
      );
    } else if (phase == SpeedTestPhase.latency) {
      final pingStr = pingMs > 0 ? '$pingMs мс' : '...';
      final pingTp = TextPainter(
        text: TextSpan(
          text: pingStr,
          style: TextStyle(
            color: textColor,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      pingTp.paint(
        canvas,
        Offset(cx - pingTp.width / 2, cy - radius * 0.70),
      );

      final labelTp = TextPainter(
        text: TextSpan(
          text: 'PING',
          style: TextStyle(
            color: secondaryTextColor,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelTp.paint(
        canvas,
        Offset(cx - labelTp.width / 2, cy - radius * 0.38),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.needleValue != needleValue ||
      old.phase != phase ||
      old.pulseValue != pulseValue ||
      old.currentSpeed != currentSpeed ||
      old.pingMs != pingMs;
}

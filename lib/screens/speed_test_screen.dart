// lib/screens/speed_test_screen.dart
//
// Экран бенчмарка скорости (как speedtest.net).
// Показывает: спидометр с анимированной стрелкой, текущую фазу теста,
// ping / jitter / download / upload.
//
// Вызов: Navigator.push → SpeedTestScreen(node: ...).
// Можно вызвать из меню «О сервере» (long press на ноде).

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ios_theme.dart';
import '../models/vpn_node.dart';
import '../logic/speed_benchmark.dart';

class SpeedTestScreen extends StatefulWidget {
  final VpnNode? node;
  const SpeedTestScreen({super.key, this.node});

  @override
  State<SpeedTestScreen> createState() => _SpeedTestScreenState();
}

class _SpeedTestScreenState extends State<SpeedTestScreen>
    with TickerProviderStateMixin {
  SpeedBenchmark? _bench;
  SpeedTestResult? _result;

  SpeedTestPhase _phase = SpeedTestPhase.idle;
  double _progress = 0;
  double _currentSpeed = 0;
  int _pingMs = 0;
  double _jitterMs = 0;

  // Финальные значения для отображения карточек
  double _downloadMbps = 0;
  double _uploadMbps = 0;

  bool _running = false;

  // Анимация стрелки спидометра
  late final AnimationController _needleCtrl;
  double _needleTarget = 0;

  // Анимация пульсации центра
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _needleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _bench?.cancel();
    _needleCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _startTest() async {
    _bench?.cancel();
    _bench = SpeedBenchmark();

    setState(() {
      _running = true;
      _result = null;
      _phase = SpeedTestPhase.idle;
      _progress = 0;
      _currentSpeed = 0;
      _pingMs = 0;
      _jitterMs = 0;
      _downloadMbps = 0;
      _uploadMbps = 0;
      _needleTarget = 0;
    });

    _pulseCtrl.repeat();

    final result = await _bench!.run(({
      required SpeedTestPhase phase,
      required double progress,
      required double currentSpeed,
      required int pingMs,
      required double jitterMs,
    }) {
      if (!mounted) return;
      setState(() {
        _phase = phase;
        _progress = progress;
        _currentSpeed = currentSpeed;
        _pingMs = pingMs;
        _jitterMs = jitterMs;

        if (phase == SpeedTestPhase.download) {
          _downloadMbps = currentSpeed;
        } else if (phase == SpeedTestPhase.upload) {
          _uploadMbps = currentSpeed;
        }

        // Обновляем стрелку: нормализуем скорость 0..500 Мбит/с → 0..1
        if (phase == SpeedTestPhase.download ||
            phase == SpeedTestPhase.upload) {
          _needleTarget = _speedToGauge(currentSpeed);
        } else if (phase == SpeedTestPhase.latency) {
          _needleTarget = progress * 0.15;
        } else {
          _needleTarget = 0;
        }
      });
    });

    if (!mounted) return;

    _pulseCtrl.stop();
    _pulseCtrl.reset();

    setState(() {
      _running = false;
      _result = result;
      _phase = SpeedTestPhase.done;
      _needleTarget = 0;
    });
  }

  /// Логарифмическая шкала: 0 Mbps → 0.0, ~500 Mbps → 1.0
  double _speedToGauge(double mbps) {
    if (mbps <= 0) return 0;
    // log scale: 0→0, 1→0.15, 10→0.4, 50→0.65, 100→0.75, 500→1.0
    return (math.log(mbps + 1) / math.log(501)).clamp(0.0, 1.0);
  }

  String _phaseLabel() {
    switch (_phase) {
      case SpeedTestPhase.idle:
        return 'Нажмите для запуска';
      case SpeedTestPhase.latency:
        return 'Измеряем задержку...';
      case SpeedTestPhase.download:
        return 'Скачивание...';
      case SpeedTestPhase.upload:
        return 'Загрузка...';
      case SpeedTestPhase.done:
        return 'Тест завершён';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
            child: Row(children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _bench?.cancel();
                  Navigator.of(context).pop();
                },
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(children: [
                    Icon(CupertinoIcons.chevron_back,
                        size: 22, color: c.textPrimary),
                    Text(' Назад',
                        style:
                            t.textStyles.body.copyWith(color: c.textPrimary)),
                  ]),
                ),
              ),
              const Spacer(),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(children: [
              Text('Тест скорости', style: t.textStyles.largeTitle),
            ]),
          ),

          // ── Подзаголовок с именем ноды ──
          if (widget.node != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(children: [
                Icon(CupertinoIcons.bolt, size: 14, color: c.textTertiary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${widget.node!.name} · ${widget.node!.address}:${widget.node!.port}',
                    style: t.textStyles.footnote
                        .copyWith(color: c.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),

          // ── Body ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              physics: const BouncingScrollPhysics(),
              children: [
                // Спидометр
                _buildGauge(t, c),
                const SizedBox(height: 16),

                // Текущая фаза
                Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      _phaseLabel(),
                      key: ValueKey(_phase),
                      style: t.textStyles.headline
                          .copyWith(color: c.textSecondary),
                    ),
                  ),
                ),

                // Прогресс-бар фазы
                if (_running) ...[
                  const SizedBox(height: 12),
                  _buildProgressBar(c),
                ],

                const SizedBox(height: 24),

                // Карточки результатов
                _buildResultCards(t, c),

                const SizedBox(height: 24),

                // Кнопка
                if (!_running)
                  IosButton(
                    label: _result != null ? 'Пройти заново' : 'Начать тест',
                    style: IosButtonStyle.primary,
                    leadingIcon: _result != null
                        ? CupertinoIcons.refresh
                        : CupertinoIcons.play_fill,
                    onPressed: _startTest,
                  ),

                if (_running)
                  IosButton(
                    label: 'Остановить',
                    style: IosButtonStyle.destructive,
                    leadingIcon: CupertinoIcons.stop_fill,
                    onPressed: () {
                      _bench?.cancel();
                      _pulseCtrl.stop();
                      _pulseCtrl.reset();
                      setState(() {
                        _running = false;
                        _phase = SpeedTestPhase.idle;
                        _needleTarget = 0;
                      });
                    },
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  СПИДОМЕТР
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildGauge(IosThemeData t, IosColors c) {
    return SizedBox(
      height: 220,
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (_, __) {
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: _needleTarget),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, needleValue, _) {
              return CustomPaint(
                size: const Size(double.infinity, 220),
                painter: _GaugePainter(
                  needleValue: needleValue,
                  phase: _phase,
                  pulseValue: _pulseCtrl.value,
                  arcColor: c.blue,
                  arcBgColor: c.fill,
                  needleColor: c.textPrimary,
                  centerColor: c.blue,
                  tickColor: c.textTertiary,
                  textColor: c.textPrimary,
                  secondaryTextColor: c.textSecondary,
                  currentSpeed: _currentSpeed,
                  pingMs: _pingMs,
                  brightness: t.brightness,
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  ПРОГРЕСС-БАР
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildProgressBar(IosColors c) {
    Color barColor;
    switch (_phase) {
      case SpeedTestPhase.latency:
        barColor = c.orange;
        break;
      case SpeedTestPhase.download:
        barColor = c.blue;
        break;
      case SpeedTestPhase.upload:
        barColor = c.green;
        break;
      default:
        barColor = c.blue;
    }

    return Container(
      height: 4,
      margin: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: c.fill,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width:
              (MediaQuery.of(context).size.width - 96) * _progress.clamp(0, 1),
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  КАРТОЧКИ РЕЗУЛЬТАТОВ
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildResultCards(IosThemeData t, IosColors c) {
    return Column(children: [
      // Ping + Jitter
      Row(children: [
        Expanded(
          child: _MetricCard(
            icon: CupertinoIcons.antenna_radiowaves_left_right,
            iconColor: c.orange,
            label: 'PING',
            value: _pingMs > 0 ? '$_pingMs' : '—',
            unit: 'мс',
            colors: c,
            textStyles: t.textStyles,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricCard(
            icon: CupertinoIcons.waveform,
            iconColor: c.orange,
            label: 'JITTER',
            value: _jitterMs > 0 ? _jitterMs.toStringAsFixed(1) : '—',
            unit: 'мс',
            colors: c,
            textStyles: t.textStyles,
          ),
        ),
      ]),
      const SizedBox(height: 8),
      // Download + Upload
      Row(children: [
        Expanded(
          child: _MetricCard(
            icon: CupertinoIcons.arrow_down_circle_fill,
            iconColor: c.blue,
            label: 'СКАЧИВАНИЕ',
            value: _downloadMbps > 0
                ? _downloadMbps.toStringAsFixed(1)
                : '—',
            unit: 'Мбит/с',
            colors: c,
            textStyles: t.textStyles,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricCard(
            icon: CupertinoIcons.arrow_up_circle_fill,
            iconColor: c.green,
            label: 'ЗАГРУЗКА',
            value:
                _uploadMbps > 0 ? _uploadMbps.toStringAsFixed(1) : '—',
            unit: 'Мбит/с',
            colors: c,
            textStyles: t.textStyles,
          ),
        ),
      ]),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  КАРТОЧКА МЕТРИКИ
// ═════════════════════════════════════════════════════════════════════════════

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

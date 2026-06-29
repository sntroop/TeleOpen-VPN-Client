// lib/screens/speed_test_screen.dart
//
// Экран бенчмарка скорости (как speedtest.net).
// Показывает: спидометр с анимированной стрелкой, текущую фазу теста,
// ping / jitter / download / upload.
//
// Вызов: Navigator.push → SpeedTestScreen(node: ...).
// Можно вызвать из меню «О сервере» (long press на ноде).

library speed_test_screen;

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ios_theme.dart';
import '../models/vpn_node.dart';
import '../logic/speed_benchmark.dart';

part 'speed_test/parts.dart';

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


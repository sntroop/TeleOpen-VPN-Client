// lib/screens/diagnostics_screen.dart
//
// Экран диагностики сервера: показывает живой прогресс серии тестов
// и финальный отчёт с оценкой качества.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ios_theme.dart';
import '../main.dart';
import '../models/vpn_node.dart';
import '../logic/diagnostics.dart';

class DiagnosticsScreen extends StatefulWidget {
  /// Если узел не задан — показываем сначала экран выбора сервера.
  final VpnNode? initialNode;
  const DiagnosticsScreen({super.key, this.initialNode});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  VpnNode? _node;
  DiagnosticsRunner? _runner;
  DiagnosticsReport? _report;
  bool _running = false;
  String _currentLabel = '';

  static const _phaseLabels = {
    'dns':   'Резолвим домен...',
    'tcp':   'Пингуем сервер по TCP...',
    'port':  'Проверяем доступность порта...',
    'tls':   'Устанавливаем TLS handshake...',
    'http':  'Стучимся по HTTP...',
    'geo':   'Определяем геолокацию...',
    'rdns':  'Запрашиваем reverse DNS...',
    'bench': 'Бенчмаркаем стабильность...',
  };

  @override
  void initState() {
    super.initState();
    if (widget.initialNode != null) {
      _node = widget.initialNode;
      // запускаем тест автоматически на следующем кадре
      WidgetsBinding.instance.addPostFrameCallback((_) => _runDiagnostics());
    }
  }

  Future<void> _runDiagnostics() async {
    if (_node == null) return;
    final runner = DiagnosticsRunner(
      node: _node!,
      onUpdate: (id, _) {
        if (!mounted) return;
        setState(() {
          _currentLabel = _phaseLabels[id] ?? 'Тестируем...';
        });
      },
    );
    setState(() {
      _runner = runner;
      _report = null;
      _running = true;
      _currentLabel = 'Запускаем диагностику...';
    });
    try {
      final report = await runner.run();
      if (!mounted) return;
      setState(() {
        _report = report;
        _running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _currentLabel = 'Ошибка: $e';
      });
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
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
            child: Row(children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(children: [
                    Icon(CupertinoIcons.chevron_back, size: 22, color: c.textPrimary),
                    Text(' Назад', style: t.textStyles.body.copyWith(color: c.textPrimary)),
                  ]),
                ),
              ),
              const Spacer(),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(children: [
              Text('Диагностика', style: t.textStyles.largeTitle),
            ]),
          ),
          Expanded(child: _buildBody(t, c)),
        ]),
      ),
    );
  }

  Widget _buildBody(IosThemeData t, IosColors c) {
    if (_node == null) {
      return _NodePicker(onSelect: (n) {
        setState(() => _node = n);
        _runDiagnostics();
      });
    }

    if (_running || _runner == null) {
      return _RunningView(
        node: _node!,
        steps: _runner?.steps ?? [],
        label: _currentLabel,
      );
    }

    return _ReportView(
      report: _report!,
      onRerun: _runDiagnostics,
      onPickAnother: () => setState(() {
        _node = null;
        _runner = null;
        _report = null;
      }),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ВЫБОР СЕРВЕРА
// ════════════════════════════════════════════════════════════════════════════

class _NodePicker extends StatelessWidget {
  final ValueChanged<VpnNode> onSelect;
  const _NodePicker({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final state = AppStateScope.of(context);
    final allNodes = state.groups.expand((g) => g.nodes).toList();

    if (allNodes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(CupertinoIcons.exclamationmark_circle, size: 48, color: c.textTertiary),
            const SizedBox(height: 12),
            Text('Нет серверов для диагностики',
                style: t.textStyles.body.copyWith(color: c.textSecondary)),
            const SizedBox(height: 4),
            Text('Сначала добавьте подписку',
                style: t.textStyles.footnote.copyWith(color: c.textTertiary)),
          ]),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      physics: const BouncingScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
          child: Text(
            'Выберите сервер для проверки. Тесты пройдут напрямую к endpoint\'у — VPN-подключение для этого не нужно.',
            style: t.textStyles.footnote.copyWith(color: c.textSecondary),
          ),
        ),
        ...state.groups.map((g) {
          if (g.nodes.isEmpty) return const SizedBox.shrink();
          return IosListSection(
            header: g.title,
            children: g.nodes
                .map((n) => IosListTile(
                      title: n.name,
                      subtitle: '${n.protocolLabel} · ${n.address}:${n.port}',
                      showChevron: true,
                      onTap: () => onSelect(n),
                    ))
                .toList(),
          );
        }),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ПРОЦЕСС
// ════════════════════════════════════════════════════════════════════════════

class _RunningView extends StatelessWidget {
  final VpnNode node;
  final List<DiagStepResult> steps;
  final String label;
  const _RunningView({required this.node, required this.steps, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      physics: const BouncingScrollPhysics(),
      children: [
        // Большая «крутилка» с описанием
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: c.bgSecondary,
            borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
          ),
          child: Column(children: [
            const _PulsingDot(),
            const SizedBox(height: 20),
            Text(node.name, style: t.textStyles.headline),
            const SizedBox(height: 4),
            Text('${node.address}:${node.port}',
                style: t.textStyles.footnote.copyWith(color: c.textSecondary)),
            const SizedBox(height: 20),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                label,
                key: ValueKey(label),
                style: t.textStyles.subheadline.copyWith(color: c.textPrimary),
                textAlign: TextAlign.center,
              ),
            ),
          ]),
        ),

        // Список тестов с их статусами
        IosListSection(
          header: 'Тесты',
          children: steps.map((s) => _StepTile(step: s)).toList(),
        ),
      ],
    );
  }
}

// Анимированный пульсирующий круг (вместо обычного спиннера — выглядит круче)
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with TickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = IosTheme.of(context).colors;
    return SizedBox(
      width: 80,
      height: 80,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          return Stack(alignment: Alignment.center, children: [
            // Три расходящихся круга
            for (var i = 0; i < 3; i++)
              _ringFor(i, c),
            // Центральная точка
            Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                color: c.blue,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: c.blue.withValues(alpha: 0.5), blurRadius: 12),
                ],
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _ringFor(int i, IosColors c) {
    final phase = ((_ctrl.value + i * 0.33) % 1.0);
    final size = 20 + phase * 60;
    final opacity = (1.0 - phase).clamp(0.0, 1.0);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c.blue.withValues(alpha: opacity * 0.5), width: 2),
      ),
    );
  }
}

// Строка одного теста (иконка статуса + название + результат)
class _StepTile extends StatelessWidget {
  final DiagStepResult step;
  const _StepTile({required this.step});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    Widget leading;
    Color titleColor = c.textPrimary;
    switch (step.status) {
      case DiagStatus.pending:
        leading = Container(
          width: 20, height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: c.textTertiary, width: 1.5),
          ),
        );
        titleColor = c.textTertiary;
        break;
      case DiagStatus.running:
        leading = SizedBox(
          width: 20, height: 20,
          child: CupertinoActivityIndicator(color: c.textPrimary, radius: 9),
        );
        break;
      case DiagStatus.ok:
        leading = Icon(CupertinoIcons.check_mark_circled_solid, size: 22, color: c.green);
        break;
      case DiagStatus.warn:
        leading = Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 20, color: c.orange);
        break;
      case DiagStatus.fail:
        leading = Icon(CupertinoIcons.xmark_circle_fill, size: 22, color: c.red);
        break;
      case DiagStatus.skipped:
        leading = Icon(CupertinoIcons.minus_circle, size: 22, color: c.textTertiary);
        titleColor = c.textTertiary;
        break;
    }

    return IosListTile(
      leading: SizedBox(width: 28, height: 28, child: Center(child: leading)),
      title: step.title,
      titleColor: titleColor,
      subtitle: step.detail,
      trailingText: step.primary,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ОТЧЁТ
// ════════════════════════════════════════════════════════════════════════════

class _ReportView extends StatelessWidget {
  final DiagnosticsReport report;
  final VoidCallback onRerun;
  final VoidCallback onPickAnother;
  const _ReportView({required this.report, required this.onRerun, required this.onPickAnother});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    final scoreColor = report.score >= 85
        ? c.green
        : report.score >= 65
            ? c.orange
            : c.red;

    final elapsed = report.finishedAt.difference(report.startedAt);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      physics: const BouncingScrollPhysics(),
      children: [
        // Карточка с оценкой
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: c.bgSecondary,
            borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
          ),
          child: Column(children: [
            Text(report.node.name, style: t.textStyles.headline),
            const SizedBox(height: 4),
            Text('${report.node.address}:${report.node.port}',
                style: t.textStyles.footnote.copyWith(color: c.textSecondary)),
            const SizedBox(height: 20),

            // Большая оценка в кружке
            Container(
              width: 120, height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scoreColor.withValues(alpha: 0.12),
                border: Border.all(color: scoreColor, width: 3),
              ),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${report.score}',
                      style: t.textStyles.largeTitle.copyWith(
                        color: scoreColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 42,
                      )),
                  Text('из 100',
                      style: t.textStyles.caption1.copyWith(color: c.textSecondary)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Text(report.verdict,
                style: t.textStyles.title3.copyWith(color: scoreColor, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('Тесты заняли ${elapsed.inSeconds}.${(elapsed.inMilliseconds % 1000) ~/ 100} с',
                style: t.textStyles.footnote.copyWith(color: c.textTertiary)),
          ]),
        ),

        // Детальный список
        IosListSection(
          header: 'Результаты',
          children: report.steps.map((s) => _StepTile(step: s)).toList(),
        ),

        const SizedBox(height: 16),

        // Кнопки
        IosButton(
          label: 'Прогнать заново',
          style: IosButtonStyle.primary,
          leadingIcon: CupertinoIcons.refresh,
          onPressed: onRerun,
        ),
        const SizedBox(height: 8),
        IosButton(
          label: 'Выбрать другой сервер',
          style: IosButtonStyle.secondary,
          leadingIcon: CupertinoIcons.square_list,
          onPressed: onPickAnother,
        ),
      ],
    );
  }
}

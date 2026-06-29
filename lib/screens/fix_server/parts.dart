// lib/screens/fix_server/parts.dart
// Типы стадий/шагов фикса и виджет одного шага плана. part of fix_server_screen.

part of '../fix_server_screen.dart';

enum _Stage { pickServer, input, connecting, loading, applying, done }

enum _StepState { pending, running, success, skipped, failed }

class _StepView {
  final FixAction action;
  _StepState state;
  _StepView(this.action) : state = _StepState.pending;
}

// ─── Виджет одного шага ─────────────────────────────────────────────────────

class _StepTile extends StatelessWidget {
  final _StepView step;
  final IosThemeData t;
  final IosColors c;
  const _StepTile({required this.step, required this.t, required this.c});

  @override
  Widget build(BuildContext context) {
    final a = step.action;

    Widget leading;
    Color bg;
    switch (step.state) {
      case _StepState.pending:
        leading = Icon(CupertinoIcons.circle, size: 18, color: c.textTertiary);
        bg = c.bgSecondary;
        break;
      case _StepState.running:
        leading = SizedBox(
          width: 18, height: 18,
          child: CupertinoActivityIndicator(radius: 9, color: c.blue),
        );
        bg = c.bgSecondary;
        break;
      case _StepState.success:
        leading = Icon(CupertinoIcons.checkmark_circle_fill, size: 20, color: c.green);
        bg = c.bgSecondary;
        break;
      case _StepState.skipped:
        leading = Icon(CupertinoIcons.minus_circle_fill, size: 20, color: c.textTertiary);
        bg = c.bgSecondary;
        break;
      case _StepState.failed:
        leading = Icon(CupertinoIcons.xmark_circle_fill, size: 20, color: c.red);
        bg = c.bgSecondary;
        break;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
        border: Border.all(
          color: step.state == _StepState.running
              ? c.blue.withValues(alpha: 0.4)
              : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: leading),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              a.label.isNotEmpty ? a.label : _defaultLabel(a),
              style: t.textStyles.body.copyWith(
                color: step.state == _StepState.skipped ? c.textTertiary : c.textPrimary,
                decoration: step.state == _StepState.skipped
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
            if (a.explanation.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                a.explanation,
                style: t.textStyles.caption1.copyWith(color: c.textTertiary),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  String _defaultLabel(FixAction a) {
    switch (a.type) {
      case FixActionType.switch_setting: return 'Меняю настройку: ${a.key} → ${a.value}';
      case FixActionType.switch_dns:     return 'Переключаю DNS на ${a.value}';
      case FixActionType.switch_server:  return 'Меняю сервер${a.targetCountry != null ? " (${a.targetCountry})" : ""}';
      case FixActionType.no_change:      return 'Ничего менять не нужно';
    }
  }
}

// ── Чистые рендеры стадий (вынесены из _FixServerScreenState) ──────────────
// Не дёргают setState — это просто отрисовка по переданному состоянию.

class _ConnectingStageView extends StatelessWidget {
  final IosThemeData t;
  final IosColors c;
  final String hint;
  const _ConnectingStageView({required this.t, required this.c, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('connecting'),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 96, height: 96,
          decoration: BoxDecoration(color: c.fill, shape: BoxShape.circle),
          child: Center(child: CupertinoActivityIndicator(radius: 18, color: c.green)),
        ),
        const SizedBox(height: 24),
        Text(hint, style: t.textStyles.title3, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Сейчас переключусь и начну диагностику',
            style: t.textStyles.subheadline.copyWith(color: c.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      ]),
    );
  }
}

class _LoadingStageView extends StatelessWidget {
  final IosThemeData t;
  final IosColors c;
  final String hint;
  final int dotsCount;
  const _LoadingStageView({required this.t, required this.c, required this.hint, required this.dotsCount});

  @override
  Widget build(BuildContext context) {
    final dots = '.' * dotsCount;
    return Center(
      key: const ValueKey('loading'),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 96, height: 96,
          decoration: BoxDecoration(color: c.fill, shape: BoxShape.circle),
          child: Center(child: CupertinoActivityIndicator(radius: 18, color: c.blue)),
        ),
        const SizedBox(height: 24),
        Text('$hint$dots', style: t.textStyles.title3),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Это займёт пару секунд',
            style: t.textStyles.subheadline.copyWith(color: c.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      ]),
    );
  }
}

class _ApplyingStageView extends StatelessWidget {
  final IosThemeData t;
  final IosColors c;
  final FixPlan plan;
  final List<_StepView> steps;
  const _ApplyingStageView({required this.t, required this.c, required this.plan, required this.steps});

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('applying'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.bgSecondary,
            borderRadius: IosShapes.continuous(IosShapes.radiusLarge),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(CupertinoIcons.wand_stars, size: 18, color: c.blue),
              const SizedBox(width: 8),
              Text('Нашёл проблему',
                  style: t.textStyles.subheadline.copyWith(
                    color: c.blue, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (plan.confidence > 0)
                Text('${plan.confidence}%',
                    style: t.textStyles.caption1.copyWith(color: c.textTertiary)),
            ]),
            const SizedBox(height: 8),
            Text(plan.diagnosis, style: t.textStyles.body),
          ]),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text('Применяю фикс',
              style: t.textStyles.footnote.copyWith(color: c.textSecondary)),
        ),
        ...steps.map((s) => _StepTile(step: s, t: t, c: c)),
      ],
    );
  }
}

// lib/screens/fix_server_screen.dart
//
// Экран "Починить сервер" (ИИ-диагностика).
//
// Стадии:
//   0. _Stage.pickServer — выбор какой сервер чинить (со списком всех нод).
//      Если юзер уже подключён к ноде, она помечена "Текущий" и стоит первой.
//   1. _Stage.input     — описание проблемы + быстрые чипы.
//   2. _Stage.connecting— если выбран не активный сервер, переподключаемся,
//                         ждём statusConnected (либо 12 сек таймаут).
//   3. _Stage.loading   — собираем диагностику, шлём на /ai/fix.
//   4. _Stage.applying  — список шагов плана, по очереди применяются.
//   5. _Stage.done      — итог + кнопка "Готово" / "Ещё раз".

// Корень библиотеки fix_server_screen. Сам экран и его State здесь; типы стадий/
// шагов и виджет шага (_StepTile) вынесены в part screens/fix_server/parts.dart.
library fix_server_screen;

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ios_theme.dart';
import '../main.dart';
import '../models/vpn_node.dart';
import '../logic/ai_fixer.dart';
import '../logic/crash_log.dart';

part 'fix_server/parts.dart';

class FixServerScreen extends StatefulWidget {
  const FixServerScreen({super.key});

  @override
  State<FixServerScreen> createState() => _FixServerScreenState();
}

class _FixServerScreenState extends State<FixServerScreen> {
  _Stage _stage = _Stage.pickServer;

  // ── выбор сервера ──
  VpnNode? _chosenNode;

  // ── переподключение ──
  String _connectingHint = 'Подключаюсь к серверу';

  // ── input стадия ──
  final TextEditingController _msgCtrl = TextEditingController();
  String _problemKey = 'generic';

  // ── loading стадия ──
  String _loadingHint = 'Анализирую соединение';
  Timer? _loadingTicker;
  int _loadingDots = 0;

  // ── applying стадия ──
  FixPlan? _plan;
  List<_StepView> _steps = [];

  // ── done стадия ──
  String? _resultMessage;
  bool _resultOk = false;
  String? _errorMessage;

  @override
  void dispose() {
    _msgCtrl.dispose();
    _loadingTicker?.cancel();
    super.dispose();
  }

  static const List<({String key, String label, IconData icon})> _quickProblems = [
    (key: 'youtube',   label: 'YouTube тормозит',   icon: CupertinoIcons.play_rectangle_fill),
    (key: 'tiktok',    label: 'TikTok не грузит',   icon: CupertinoIcons.music_note),
    (key: 'discord',   label: 'Discord виснет',     icon: CupertinoIcons.chat_bubble_2_fill),
    (key: 'instagram', label: 'Instagram',          icon: CupertinoIcons.camera_fill),
    (key: 'telegram',  label: 'Telegram',           icon: CupertinoIcons.paperplane_fill),
    (key: 'roblox',    label: 'Roblox',             icon: CupertinoIcons.game_controller_solid),
    (key: 'chatgpt',   label: 'ChatGPT',            icon: CupertinoIcons.sparkles),
    (key: 'generic',   label: 'Всё медленно',       icon: CupertinoIcons.wifi_exclamationmark),
  ];

  // ════════════════════════════════════════════════════════════════════════
  //  Логика
  // ════════════════════════════════════════════════════════════════════════

  void _pickServer(VpnNode node) {
    HapticFeedback.selectionClick();
    setState(() {
      _chosenNode = node;
      _stage = _Stage.input;
    });
  }

  /// Юзер нажал "Починить" — если выбранный сервер не совпадает с активным,
  /// сперва подключаемся к нему, потом запускаем диагностику.
  Future<void> _startFix() async {
    final state = AppStateScope.of(context, listen: false);
    final msg = _msgCtrl.text.trim();

    if (msg.isEmpty && _problemKey == 'generic') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Опиши проблему или выбери один из вариантов'),
      ));
      return;
    }

    final target = _chosenNode;
    if (target == null) {
      setState(() => _stage = _Stage.pickServer);
      return;
    }

    HapticFeedback.mediumImpact();

    // Нужно ли переподключаться?
    final isAlreadyActive = state.activeNode?.id == target.id &&
                            state.status == VpnStatus.connected;

    if (!isAlreadyActive) {
      setState(() {
        _stage = _Stage.connecting;
        _connectingHint = 'Подключаюсь к ${target.name}';
      });

      // ВАЖНО: connect() внутри синхронно вызывает notifyListeners(), что
      // триггерит ребилд дерева. Если дёрнуть его прямо здесь — во время
      // текущего кадра — Flutter бросит "setState() called during build".
      // Поэтому: сначала ставим слушатель, потом запускаем connect отдельной
      // микротаской (вне фазы build), и только потом ждём результат.
      final connected = _waitConnected(state, target.id, const Duration(seconds: 15));

      Future<void>.microtask(() async {
        try {
          // Если уже идёт другое подключение — connect() молча выйдет.
          // Дождёмся завершения и попробуем снова.
          if (state.status == VpnStatus.connecting &&
              state.activeNode?.id != target.id) {
            await Future.delayed(const Duration(milliseconds: 800));
          }
          await state.connect(target);
        } catch (_) {/* поймаем по статусу через listener */}
      });

      final ok = await connected;
      if (!mounted) return;

      if (!ok) {
        // Не подключились — всё равно идём в диагностику: probes покажут,
        // что сервер не отвечает, и ИИ предложит сменить.
        setState(() => _connectingHint = 'Сервер не ответил, всё равно проверяю');
        await Future.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
      }
    }

    setState(() {
      _stage = _Stage.loading;
      _loadingHint = 'Анализирую соединение';
      _loadingDots = 0;
      _errorMessage = null;
    });

    _loadingTicker?.cancel();
    _loadingTicker = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      setState(() => _loadingDots = (_loadingDots + 1) % 4);
    });

    try {
      setState(() => _loadingHint = 'Проверяю серверы и DNS');
      final snapshot = await AiFixer.collect(
        state: state,
        problemKey: _problemKey,
      );

      setState(() => _loadingHint = 'Спрашиваю ИИ');
      final plan = await AiFixer.requestFix(
        snapshot: snapshot,
        userMessage: msg.isEmpty ? _problemLabel(_problemKey) : msg,
        problemKey: _problemKey,
        telegramId: state.currentUser?.id,
      );

      _loadingTicker?.cancel();
      if (!mounted) return;

      if (plan.actions.isEmpty ||
          (plan.actions.length == 1 && plan.actions.first.type == FixActionType.no_change)) {
        setState(() {
          _stage = _Stage.done;
          _plan = plan;
          _resultOk = false;
          _resultMessage = plan.diagnosis.isNotEmpty
              ? plan.diagnosis
              : 'Не нашёл явной причины. Попробуй вручную переключить сервер.';
        });
        return;
      }

      setState(() {
        _plan = plan;
        _steps = plan.actions.map((a) => _StepView(a)).toList();
        _stage = _Stage.applying;
      });

      _runSteps();
    } catch (e) {
      _loadingTicker?.cancel();
      if (!mounted) return;

      // Аккуратное человекочитаемое сообщение в зависимости от типа ошибки.
      final err = e.toString();
      String friendly;
      if (err.contains('AI provider unreachable') || err.contains('SocketException')) {
        friendly =
            'Не получилось связаться с ИИ. Возможно, сервер ИИ временно недоступен или у тебя проблемы с сетью.';
      } else if (err.contains('429')) {
        friendly = 'Слишком много запросов. Подожди минуту и попробуй ещё раз.';
      } else if (err.contains('TimeoutException')) {
        friendly = 'ИИ отвечает слишком долго. Попробуй ещё раз.';
      } else {
        friendly = 'Что-то пошло не так. Попробуй ещё раз.';
      }

      setState(() {
        _stage = _Stage.done;
        _resultOk = false;
        _errorMessage = err.replaceFirst('Exception: ', '');
        _resultMessage = friendly;
      });
    }
  }

  /// Ждём пока AppState.activeNode.id == targetId и status == connected.
  /// Возвращает true если успели за timeout, false иначе.
  Future<bool> _waitConnected(AppState state, String targetId, Duration timeout) async {
    if (state.activeNode?.id == targetId && state.status == VpnStatus.connected) {
      return true;
    }

    final completer = Completer<bool>();
    late VoidCallback listener;

    listener = () {
      if (state.activeNode?.id == targetId && state.status == VpnStatus.connected) {
        if (!completer.isCompleted) completer.complete(true);
      } else if (state.status == VpnStatus.error) {
        if (!completer.isCompleted) completer.complete(false);
      }
    };
    state.addListener(listener);

    final to = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });

    final ok = await completer.future;
    to.cancel();
    state.removeListener(listener);
    return ok;
  }

  Future<void> _runSteps() async {
    final state = AppStateScope.of(context, listen: false);

    for (int i = 0; i < _steps.length; i++) {
      if (!mounted) return;
      setState(() {
        _steps[i].state = _StepState.running;
      });

      await Future.delayed(const Duration(milliseconds: 700));

      bool changed = false;
      try {
        changed = await AiFixer.applyAction(
          state: state,
          action: _steps[i].action,
        );
      } catch (e, st) {
        // Шаг плана не применился — помечаем как пропущенный, но фиксируем
        // причину: молча «skipped» скрывает баги в применении AI-фиксов.
        CrashLog.record(e, st, 'aifix.apply');
        changed = false;
      }

      if (!mounted) return;
      setState(() {
        _steps[i].state = changed ? _StepState.success : _StepState.skipped;
      });

      HapticFeedback.lightImpact();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (!mounted) return;
    final anyChanged = _steps.any((s) => s.state == _StepState.success);
    setState(() {
      _stage = _Stage.done;
      _resultOk = anyChanged;
      _resultMessage = anyChanged
          ? 'Готово. Проверь приложение — должно работать лучше.'
          : 'ИИ предложил план, но настройки уже стояли как надо. Попробуй вручную сменить сервер.';
    });
    HapticFeedback.mediumImpact();
  }

  String _problemLabel(String key) {
    return _quickProblems.firstWhere(
      (p) => p.key == key,
      orElse: () => (key: 'generic', label: 'Всё медленно', icon: CupertinoIcons.wifi),
    ).label;
  }

  // ════════════════════════════════════════════════════════════════════════
  //  Build
  // ════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(t, c),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _buildStage(t, c),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader(IosThemeData t, IosColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
      child: Row(children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            // На стадии input — назад в выбор сервера. На остальных — закрытие.
            if (_stage == _Stage.input) {
              setState(() => _stage = _Stage.pickServer);
              return;
            }
            Navigator.of(context).pop();
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Icon(CupertinoIcons.chevron_back, size: 22, color: c.textPrimary),
              Text(
                _stage == _Stage.input ? ' Сервер' : ' Назад',
                style: t.textStyles.body.copyWith(color: c.textPrimary),
              ),
            ]),
          ),
        ),
        const Spacer(),
      ]),
    );
  }

  Widget _buildStage(IosThemeData t, IosColors c) {
    switch (_stage) {
      case _Stage.pickServer: return _buildPickServerStage(t, c);
      case _Stage.input:      return _buildInputStage(t, c);
      case _Stage.connecting: return _buildConnectingStage(t, c);
      case _Stage.loading:    return _buildLoadingStage(t, c);
      case _Stage.applying:   return _buildApplyingStage(t, c);
      case _Stage.done:       return _buildDoneStage(t, c);
    }
  }

  // ── Stage 0: выбор сервера ────────────────────────────────────────────

  Widget _buildPickServerStage(IosThemeData t, IosColors c) {
    final state = AppStateScope.of(context);
    final groups = state.groups;
    final active = state.activeNode;

    // Плоский список нод, активная (если есть) — первой.
    final allNodes = <VpnNode>[];
    if (active != null) allNodes.add(active);
    for (final g in groups) {
      for (final n in g.nodes) {
        if (n.id != active?.id) allNodes.add(n);
      }
    }

    if (allNodes.isEmpty) {
      return Center(
        key: const ValueKey('pickEmpty'),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(CupertinoIcons.exclamationmark_circle, size: 48, color: c.textTertiary),
            const SizedBox(height: 12),
            Text('Нет серверов', style: t.textStyles.title3),
            const SizedBox(height: 6),
            Text(
              'Сначала добавь подписку или сервер вручную, потом возвращайся сюда.',
              style: t.textStyles.subheadline.copyWith(color: c.textSecondary),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      );
    }

    return ListView(
      key: const ValueKey('pick'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text('Какой сервер чинить?', style: t.textStyles.largeTitle),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 20),
          child: Text(
            'Выбери сервер — приложение подключится к нему и проверит что не так.',
            style: t.textStyles.subheadline.copyWith(color: c.textSecondary),
          ),
        ),

        ...allNodes.map((n) {
          final isActive = n.id == active?.id;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _pickServer(n),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: c.bgSecondary,
                  borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
                  border: Border.all(
                    color: isActive ? c.green : Colors.transparent,
                    width: 1.4,
                  ),
                ),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: isActive ? c.green : c.fill,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isActive ? CupertinoIcons.checkmark_alt : CupertinoIcons.globe,
                      size: 20,
                      color: isActive ? Colors.white : c.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(n.name,
                          style: t.textStyles.body,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Row(children: [
                        Text(n.protocolLabel,
                            style: t.textStyles.caption1.copyWith(color: c.textTertiary)),
                        if (isActive) ...[
                          Text(' · ',
                              style: t.textStyles.caption1.copyWith(color: c.textTertiary)),
                          Text('Текущий',
                              style: t.textStyles.caption1.copyWith(
                                color: c.green, fontWeight: FontWeight.w600)),
                        ],
                        if (n.pingMs != null) ...[
                          Text(' · ',
                              style: t.textStyles.caption1.copyWith(color: c.textTertiary)),
                          Text('${n.pingMs} мс',
                              style: t.textStyles.caption1.copyWith(color: c.textTertiary)),
                        ],
                      ]),
                    ]),
                  ),
                  Icon(CupertinoIcons.chevron_right, size: 16, color: c.textTertiary),
                ]),
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── Stage 1: ввод ──────────────────────────────────────────────────────

  Widget _buildInputStage(IosThemeData t, IosColors c) {
    final node = _chosenNode;

    return ListView(
      key: const ValueKey('input'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text('Что не работает?', style: t.textStyles.largeTitle),
        ),

        // Карточка выбранного сервера
        if (node != null)
          Container(
            margin: const EdgeInsets.fromLTRB(0, 8, 0, 18),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.bgSecondary,
              borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
            ),
            child: Row(children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: c.blue, borderRadius: BorderRadius.circular(8)),
                child: const Icon(CupertinoIcons.globe, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Чиним сервер',
                      style: t.textStyles.caption1.copyWith(color: c.textTertiary)),
                  Text(node.name,
                      style: t.textStyles.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _stage = _Stage.pickServer),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Text('Сменить',
                      style: t.textStyles.subheadline.copyWith(
                          color: c.blue, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),

        // Поле ввода
        Container(
          decoration: BoxDecoration(
            color: c.bgSecondary,
            borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: TextField(
            controller: _msgCtrl,
            maxLines: 4,
            minLines: 3,
            maxLength: 500,
            style: t.textStyles.body,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText:
                  'Например: «Ютуб открывается, но видео грузится по часу» или «Дискорд режет голос только дома».',
              hintStyle: t.textStyles.body.copyWith(color: c.textTertiary),
              counterText: '',
            ),
          ),
        ),

        const SizedBox(height: 24),

        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            'Или выбери что не работает',
            style: t.textStyles.footnote.copyWith(color: c.textSecondary),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _quickProblems.map((p) {
            final selected = _problemKey == p.key;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _problemKey = p.key);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: selected ? c.blue : c.bgSecondary,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected ? c.blue : c.fill,
                    width: 1,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(p.icon, size: 15,
                      color: selected ? Colors.white : c.textPrimary),
                  const SizedBox(width: 6),
                  Text(p.label,
                      style: t.textStyles.subheadline.copyWith(
                        color: selected ? Colors.white : c.textPrimary,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      )),
                ]),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 32),

        IosButton(
          label: 'Починить',
          onPressed: _startFix,
        ),

        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'ИИ читает только настройки и логи подключения. Личные данные не передаются.',
            style: t.textStyles.caption1.copyWith(color: c.textTertiary),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  // ── Stage 2: подключение к выбранному серверу ─────────────────────────

  Widget _buildConnectingStage(IosThemeData t, IosColors c) =>
      _ConnectingStageView(t: t, c: c, hint: _connectingHint);

  // ── Stage 3: загрузка ──────────────────────────────────────────────────

  Widget _buildLoadingStage(IosThemeData t, IosColors c) =>
      _LoadingStageView(t: t, c: c, hint: _loadingHint, dotsCount: _loadingDots);

  // ── Stage 4: применение шагов ─────────────────────────────────────────

  Widget _buildApplyingStage(IosThemeData t, IosColors c) {
    final plan = _plan;
    if (plan == null) return const SizedBox.shrink();
    return _ApplyingStageView(t: t, c: c, plan: plan, steps: _steps);
  }

  // ── Stage 5: done ──────────────────────────────────────────────────────

  Widget _buildDoneStage(IosThemeData t, IosColors c) {
    return ListView(
      key: const ValueKey('done'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Center(
          child: Container(
            width: 96, height: 96,
            margin: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: _resultOk ? c.green.withValues(alpha: 0.18) : c.orange.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _resultOk
                  ? CupertinoIcons.checkmark_alt
                  : CupertinoIcons.exclamationmark,
              size: 48,
              color: _resultOk ? c.green : c.orange,
            ),
          ),
        ),

        Text(
          _resultOk ? 'Готово' : 'Не помогло',
          style: t.textStyles.title1,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _resultMessage ?? '',
            style: t.textStyles.body.copyWith(color: c.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.bgSecondary,
              borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
            ),
            child: Text(
              _errorMessage!,
              style: t.textStyles.caption1.copyWith(color: c.textTertiary),
            ),
          ),
        ],

        const SizedBox(height: 32),

        IosButton(
          label: 'Готово',
          onPressed: () => Navigator.of(context).pop(),
        ),

        if (!_resultOk) ...[
          const SizedBox(height: 10),
          IosButton(
            label: 'Попробовать ещё раз',
            style: IosButtonStyle.secondary,
            onPressed: () {
              setState(() {
                _stage = _Stage.input;
                _plan = null;
                _steps = [];
                _resultMessage = null;
                _errorMessage = null;
              });
            },
          ),
        ],
      ],
    );
  }
}

// lib/screens/statistics_screen.dart
//
// Экран статистики использования VPN.
// Показывает: историю сессий, топ серверов по времени/трафику,
// суммарный трафик, красивый bar-chart по дням.
//
// Корень библиотеки statistics_screen. Здесь модель/storage, экран и его State;
// вспомогательные виджеты (карточки/график/тайлы) и форматтеры вынесены в
// part-файлы screens/statistics/. Путь файла не менялся → импорты не трогаются.

library statistics_screen;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ios_theme.dart';
import '../main.dart';

part 'statistics/charts.dart';
part 'statistics/tiles.dart';
part 'statistics/format.dart';

// ════════════════════════════════════════════════════════════════════════════
// MODEL
// ════════════════════════════════════════════════════════════════════════════

class SessionRecord {
  final String nodeId;
  final String nodeName;
  final String protocol;
  final DateTime startedAt;
  final int durationSec;   // секунды
  final int rxBytes;
  final int txBytes;

  const SessionRecord({
    required this.nodeId,
    required this.nodeName,
    required this.protocol,
    required this.startedAt,
    required this.durationSec,
    required this.rxBytes,
    required this.txBytes,
  });

  int get totalBytes => rxBytes + txBytes;

  Map<String, dynamic> toJson() => {
    'nodeId':      nodeId,
    'nodeName':    nodeName,
    'protocol':    protocol,
    'startedAt':   startedAt.millisecondsSinceEpoch,
    'durationSec': durationSec,
    'rxBytes':     rxBytes,
    'txBytes':     txBytes,
  };

  factory SessionRecord.fromJson(Map<String, dynamic> j) => SessionRecord(
    nodeId:      j['nodeId'] as String,
    nodeName:    j['nodeName'] as String,
    protocol:    j['protocol'] as String,
    startedAt:   DateTime.fromMillisecondsSinceEpoch(j['startedAt'] as int),
    durationSec: j['durationSec'] as int,
    rxBytes:     j['rxBytes'] as int,
    txBytes:     j['txBytes'] as int,
  );
}

// ════════════════════════════════════════════════════════════════════════════
// STORAGE HELPER
// ════════════════════════════════════════════════════════════════════════════

class SessionStorage {
  static const _key = 'vpn_sessions';
  static const _maxSessions = 200;

  static Future<List<SessionRecord>> load(SharedPreferences prefs) async {
    final raw = prefs.getStringList(_key) ?? [];
    final result = <SessionRecord>[];
    for (final s in raw) {
      try {
        result.add(SessionRecord.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {}
    }
    return result;
  }

  static Future<void> save(SharedPreferences prefs, List<SessionRecord> sessions) async {
    final list = sessions
        .take(_maxSessions)
        .map((s) => jsonEncode(s.toJson()))
        .toList();
    await prefs.setStringList(_key, list);
  }

  static Future<void> append(SharedPreferences prefs, SessionRecord record) async {
    final existing = await load(prefs);
    final updated = [record, ...existing];
    await save(prefs, updated);
  }

  static Future<void> clear(SharedPreferences prefs) async {
    await prefs.remove(_key);
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SCREEN
// ════════════════════════════════════════════════════════════════════════════

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  List<SessionRecord> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = AppStateScope.of(context, listen: false).prefs;
    final sessions = await SessionStorage.load(prefs);
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    }
  }

  Future<void> _confirmClear() async {
    final prefs = AppStateScope.of(context, listen: false).prefs;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Очистить историю?'),
        content: const Text('Все данные о сессиях будут удалены безвозвратно.'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await SessionStorage.clear(prefs);
      await _load();
    }
  }

  // ── Агрегаты ──────────────────────────────────────────────────────────

  int get _totalRx => _sessions.fold(0, (a, s) => a + s.rxBytes);
  int get _totalTx => _sessions.fold(0, (a, s) => a + s.txBytes);
  int get _totalSec => _sessions.fold(0, (a, s) => a + s.durationSec);

  /// Трафик за последние 7 дней (индекс 0 = сегодня).
  List<_DayBar> get _weekBars {
    final now = DateTime.now();
    final bars = List.generate(7, (i) {
      final day = now.subtract(Duration(days: i));
      final dayStr = '${day.day}/${day.month}';
      return _DayBar(label: i == 0 ? 'Сег' : dayStr, rx: 0, tx: 0);
    });
    for (final s in _sessions) {
      final diff = now.difference(s.startedAt).inDays;
      if (diff >= 0 && diff < 7) {
        bars[diff] = _DayBar(
          label: bars[diff].label,
          rx: bars[diff].rx + s.rxBytes,
          tx: bars[diff].tx + s.txBytes,
        );
      }
    }
    return bars.reversed.toList(); // старый → новый (слева → справа)
  }

  /// Топ-5 серверов по суммарному трафику.
  List<_NodeStat> get _topNodes {
    final map = <String, _NodeStat>{};
    for (final s in _sessions) {
      final existing = map[s.nodeId];
      if (existing == null) {
        map[s.nodeId] = _NodeStat(
          name: s.nodeName,
          protocol: s.protocol,
          sessions: 1,
          totalBytes: s.totalBytes,
          totalSec: s.durationSec,
        );
      } else {
        map[s.nodeId] = _NodeStat(
          name: existing.name,
          protocol: existing.protocol,
          sessions: existing.sessions + 1,
          totalBytes: existing.totalBytes + s.totalBytes,
          totalSec: existing.totalSec + s.durationSec,
        );
      }
    }
    final list = map.values.toList()
      ..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
    return list.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Шапка ──────────────────────────────────────────────────
            SliverToBoxAdapter(child: _buildHeader(t, c)),

            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (_sessions.isEmpty)
              SliverFillRemaining(child: _buildEmpty(t, c))
            else ...[
              // ── Суммарные карточки ──────────────────────────────────
              SliverToBoxAdapter(child: _buildSummary(t, c)),

              // ── График по дням ──────────────────────────────────────
              SliverToBoxAdapter(child: _buildWeekChart(t, c)),

              // ── Топ серверов ────────────────────────────────────────
              SliverToBoxAdapter(child: _buildTopNodes(t, c)),

              // ── Последние сессии ────────────────────────────────────
              SliverToBoxAdapter(child: _buildRecentSessions(t, c)),

              // ── Кнопка очистки ─────────────────────────────────────
              SliverToBoxAdapter(child: _buildClearButton(t, c)),
            ],

            SliverToBoxAdapter(
              child: SizedBox(height: MediaQuery.of(context).padding.bottom + 32),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Шапка ──────────────────────────────────────────────────────────────

  Widget _buildHeader(IosThemeData t, IosColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
      child: Row(
        children: [
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
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text('Статистика', style: t.textStyles.headline),
          ),
          const Spacer(),
          const SizedBox(width: 70), // баланс
        ],
      ),
    );
  }

  // ─── Пустое состояние ───────────────────────────────────────────────────

  Widget _buildEmpty(IosThemeData t, IosColors c) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.chart_bar_square, size: 64, color: c.textQuaternary),
          const SizedBox(height: 16),
          Text('Нет данных', style: t.textStyles.headline.copyWith(color: c.textPrimary)),
          const SizedBox(height: 6),
          Text(
            'Подключитесь к VPN — статистика\nначнёт собираться автоматически.',
            style: t.textStyles.footnote.copyWith(color: c.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ─── Суммарные карточки ─────────────────────────────────────────────────

  Widget _buildSummary(IosThemeData t, IosColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ОБЩЕЕ',
            style: t.textStyles.footnote.copyWith(
              color: c.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _SummaryCard(
                t: t, c: c,
                icon: CupertinoIcons.arrow_down_circle_fill,
                color: c.green,
                label: 'Скачано',
                value: _formatBytes(_totalRx),
              )),
              const SizedBox(width: 10),
              Expanded(child: _SummaryCard(
                t: t, c: c,
                icon: CupertinoIcons.arrow_up_circle_fill,
                color: c.blue,
                label: 'Отправлено',
                value: _formatBytes(_totalTx),
              )),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _SummaryCard(
                t: t, c: c,
                icon: CupertinoIcons.clock_fill,
                color: c.orange,
                label: 'Время в VPN',
                value: _formatDurationLong(_totalSec),
              )),
              const SizedBox(width: 10),
              Expanded(child: _SummaryCard(
                t: t, c: c,
                icon: CupertinoIcons.number_circle_fill,
                color: c.purple,
                label: 'Сессий',
                value: '${_sessions.length}',
              )),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ─── График по дням ─────────────────────────────────────────────────────

  Widget _buildWeekChart(IosThemeData t, IosColors c) {
    final bars = _weekBars;
    final maxBytes = bars.fold<int>(
      1,
      (m, b) => math.max(m, b.rx + b.tx),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.bgSecondary,
          borderRadius: IosShapes.continuous(IosShapes.radiusLarge),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Трафик за 7 дней', style: t.textStyles.headline),
            const SizedBox(height: 4),
            Row(children: [
              _LegendDot(color: c.green), const SizedBox(width: 4),
              Text('↓ Download', style: t.textStyles.caption2.copyWith(color: c.textSecondary)),
              const SizedBox(width: 12),
              _LegendDot(color: c.blue), const SizedBox(width: 4),
              Text('↑ Upload', style: t.textStyles.caption2.copyWith(color: c.textSecondary)),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              child: _WeekBarChart(bars: bars, maxBytes: maxBytes, rxColor: c.green, txColor: c.blue),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: bars.map((b) => Expanded(
                child: Text(
                  b.label,
                  style: t.textStyles.caption2.copyWith(color: c.textSecondary),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Топ серверов ───────────────────────────────────────────────────────

  Widget _buildTopNodes(IosThemeData t, IosColors c) {
    final top = _topNodes;
    if (top.isEmpty) return const SizedBox.shrink();

    final maxBytes = top.first.totalBytes;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ТОП СЕРВЕРОВ',
            style: t.textStyles.footnote.copyWith(color: c.textSecondary, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: c.bgSecondary,
              borderRadius: IosShapes.continuous(IosShapes.radiusLarge),
            ),
            child: Column(
              children: List.generate(top.length, (i) {
                final node = top[i];
                final ratio = maxBytes > 0 ? node.totalBytes / maxBytes : 0.0;
                return Column(
                  children: [
                    _NodeStatTile(t: t, c: c, node: node, ratio: ratio, rank: i + 1),
                    if (i < top.length - 1)
                      Container(
                        margin: const EdgeInsets.only(left: 54),
                        height: 0.5,
                        color: c.separator,
                      ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Последние сессии ───────────────────────────────────────────────────

  Widget _buildRecentSessions(IosThemeData t, IosColors c) {
    final recent = _sessions.take(10).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ИСТОРИЯ СЕССИЙ',
            style: t.textStyles.footnote.copyWith(color: c.textSecondary, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: c.bgSecondary,
              borderRadius: IosShapes.continuous(IosShapes.radiusLarge),
            ),
            child: Column(
              children: List.generate(recent.length, (i) {
                final s = recent[i];
                return Column(
                  children: [
                    _SessionTile(t: t, c: c, session: s),
                    if (i < recent.length - 1)
                      Container(
                        margin: const EdgeInsets.only(left: 54),
                        height: 0.5,
                        color: c.separator,
                      ),
                  ],
                );
              }),
            ),
          ),
          if (_sessions.length > 10)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Показаны последние 10 из ${_sessions.length} сессий',
                style: t.textStyles.footnote.copyWith(color: c.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Кнопка очистки ─────────────────────────────────────────────────────

  Widget _buildClearButton(IosThemeData t, IosColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: IosListSection(
        children: [
          IosListTile(
            leadingIcon: CupertinoIcons.trash,
            leadingIconBg: c.red,
            title: 'Очистить историю',
            onTap: _confirmClear,
            showChevron: false,
          ),
        ],
      ),
    );
  }
}


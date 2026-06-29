// lib/screens/routing_rules_screen.dart
//
// Редактор пользовательских правил маршрутизации (в стиле Happ).
// Каждое правило: чем сопоставляем (geosite-категория / geoip-страна / домен /
// IP-CIDR) → действие (proxy / direct / block). Порядок = приоритет
// (перетаскиванием). Список уходит в AppSettings.routingRules и применяется
// нативом в HysteriaTunVpnService.ensureTunInbound.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ios_theme.dart';
import '../models/routing_rule.dart';

class RoutingRulesScreen extends StatefulWidget {
  final List<RoutingRule> initial;
  final ValueChanged<List<RoutingRule>> onChanged;

  const RoutingRulesScreen({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<RoutingRulesScreen> createState() => _RoutingRulesScreenState();
}

class _RoutingRulesScreenState extends State<RoutingRulesScreen> {
  late List<RoutingRule> _rules;

  @override
  void initState() {
    super.initState();
    _rules = widget.initial.map((r) => r.copy()).toList();
  }

  void _commit() => widget.onChanged(_rules.map((r) => r.copy()).toList());

  Future<void> _addOrEdit({RoutingRule? existing, int? index}) async {
    final result = await showModalBottomSheet<RoutingRule>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RuleEditorSheet(initial: existing),
    );
    if (result == null) return;
    setState(() {
      if (index != null) {
        _rules[index] = result;
      } else {
        _rules.add(result);
      }
    });
    _commit();
  }

  void _delete(int index) {
    setState(() => _rules.removeAt(index));
    _commit();
  }

  void _toggle(int index, bool v) {
    setState(() => _rules[index].enabled = v);
    _commit();
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final r = _rules.removeAt(oldIndex);
      _rules.insert(newIndex, r);
    });
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onAdd: () => _addOrEdit()),
            Expanded(
              child: _rules.isEmpty
                  ? _EmptyState()
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
                      physics: const BouncingScrollPhysics(),
                      itemCount: _rules.length,
                      onReorder: _reorder,
                      itemBuilder: (ctx, i) {
                        final r = _rules[i];
                        return _RuleCard(
                          key: ValueKey('rule_${i}_${r.kind.id}_${r.value}'),
                          index: i,
                          rule: r,
                          onTap: () => _addOrEdit(existing: r, index: i),
                          onToggle: (v) => _toggle(i, v),
                          onDelete: () => _delete(i),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onAdd;
  const _Header({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
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
          const SizedBox(width: 4),
          Text('Правила', style: t.textStyles.title3),
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAdd,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(CupertinoIcons.add_circled_solid, size: 26, color: c.blue),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.list_bullet_indent, size: 48, color: c.textQuaternary),
            const SizedBox(height: 12),
            Text('Нет правил', style: t.textStyles.headline),
            const SizedBox(height: 6),
            Text(
              'Добавьте правило, чтобы направлять трафик по geosite / geoip / домену '
              'через VPN, напрямую или в блок. Порядок задаёт приоритет — '
              'перетаскивайте.',
              textAlign: TextAlign.center,
              style: t.textStyles.footnote.copyWith(color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  final int index;
  final RoutingRule rule;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  const _RuleCard({
    super.key,
    required this.index,
    required this.rule,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  Color _actionColor(IosColors c) => switch (rule.action) {
        RuleAction.proxy => c.blue,
        RuleAction.direct => c.green,
        RuleAction.block => c.red,
      };

  String _actionShort() => switch (rule.action) {
        RuleAction.proxy => 'proxy',
        RuleAction.direct => 'direct',
        RuleAction.block => 'block',
      };

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final dim = !rule.enabled;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.bgSecondary,
        borderRadius: IosShapes.continuous(IosShapes.radiusLarge),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(IosShapes.radiusLarge),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(CupertinoIcons.line_horizontal_3,
                        size: 20, color: c.textQuaternary),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rule.display,
                        style: t.textStyles.body.copyWith(
                          color: dim ? c.textQuaternary : c.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: _actionColor(c).withValues(alpha: dim ? 0.12 : 0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _actionShort(),
                              style: t.textStyles.caption2.copyWith(
                                color: dim ? c.textQuaternary : _actionColor(c),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(rule.kind.label.split(' ').first,
                              style: t.textStyles.caption2
                                  .copyWith(color: c.textSecondary)),
                        ],
                      ),
                    ],
                  ),
                ),
                IosSwitch(value: rule.enabled, onChanged: onToggle),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onDelete,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(CupertinoIcons.minus_circle, size: 22, color: c.red),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Лист-шит создания/редактирования правила ────────────────────────────────

class _RuleEditorSheet extends StatefulWidget {
  final RoutingRule? initial;
  const _RuleEditorSheet({this.initial});

  @override
  State<_RuleEditorSheet> createState() => _RuleEditorSheetState();
}

class _RuleEditorSheetState extends State<_RuleEditorSheet> {
  late RuleKind _kind;
  late RuleAction _action;
  late final TextEditingController _ctrl;

  // Частые geosite-категории для быстрого выбора.
  static const _geositePresets = [
    'category-ads-all', 'telegram', 'netflix', 'youtube', 'google',
    'twitter', 'instagram', 'spotify', 'category-porn', 'private',
  ];

  @override
  void initState() {
    super.initState();
    _kind = widget.initial?.kind ?? RuleKind.geosite;
    _action = widget.initial?.action ?? RuleAction.proxy;
    _ctrl = TextEditingController(text: widget.initial?.value ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    Navigator.of(context).pop(RoutingRule(
      kind: _kind,
      value: v,
      action: _action,
      enabled: widget.initial?.enabled ?? true,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        margin: EdgeInsets.fromLTRB(8, 0, 8, MediaQuery.of(context).padding.bottom + 8),
        decoration: BoxDecoration(
          color: c.bgSecondary,
          borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 6),
                alignment: Alignment.center,
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: c.textQuaternary, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(children: [
                  Text(widget.initial == null ? 'Новое правило' : 'Правило',
                      style: t.textStyles.headline),
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(CupertinoIcons.xmark_circle_fill,
                        size: 28, color: c.textQuaternary),
                  ),
                ]),
              ),

              _sectionLabel(t, c, 'СОПОСТАВЛЯТЬ ПО'),
              ...RuleKind.values.map((k) => _choiceTile(
                    t, c,
                    label: k.label,
                    selected: _kind == k,
                    onTap: () => setState(() => _kind = k),
                  )),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: IosField(
                  controller: _ctrl,
                  label: 'Значение',
                  placeholder: _kind.hint,
                  keyboardType: TextInputType.text,
                  onChanged: (_) {},
                ),
              ),
              if (_kind == RuleKind.geosite)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _geositePresets
                        .map((p) => GestureDetector(
                              onTap: () => setState(() => _ctrl.text = p),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: c.fill,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(p,
                                    style: t.textStyles.caption1
                                        .copyWith(color: c.textPrimary)),
                              ),
                            ))
                        .toList(),
                  ),
                ),

              _sectionLabel(t, c, 'ДЕЙСТВИЕ'),
              ...RuleAction.values.map((a) => _choiceTile(
                    t, c,
                    label: a.label,
                    selected: _action == a,
                    onTap: () => setState(() => _action = a),
                  )),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: IosButton(
                  label: 'Сохранить',
                  style: IosButtonStyle.primary,
                  onPressed: _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(IosThemeData t, IosColors c, String s) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Text(s,
            style: t.textStyles.footnote
                .copyWith(color: c.textSecondary, letterSpacing: 0.5)),
      );

  Widget _choiceTile(IosThemeData t, IosColors c,
          {required String label,
          required bool selected,
          required VoidCallback onTap}) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          child: Row(
            children: [
              Expanded(child: Text(label, style: t.textStyles.body)),
              if (selected)
                Icon(CupertinoIcons.check_mark, size: 18, color: c.blue),
            ],
          ),
        ),
      );
}

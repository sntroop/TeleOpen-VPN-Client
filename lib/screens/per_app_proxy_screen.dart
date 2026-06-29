// lib/screens/per_app_proxy_screen.dart
//
// Split-tunnel: выбор приложений, которые идут через VPN.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';

import '../ios_theme.dart';
import '../main.dart';
import '../models/per_app_proxy.dart';
import '../models/per_app_preset.dart';
import '../logic/crash_log.dart';

class PerAppProxyScreen extends StatefulWidget {
  const PerAppProxyScreen({super.key});

  @override
  State<PerAppProxyScreen> createState() => _PerAppProxyScreenState();
}

class _PerAppProxyScreenState extends State<PerAppProxyScreen> {
  late PerAppProxySettings _settings;
  final _searchCtrl = TextEditingController();
  String _query = '';
  List<AppInfo> _apps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _settings = PerAppProxySettings(
      enabled: AppStateScope.of(context, listen: false).perApp.enabled,
      includedPackages: List.from(AppStateScope.of(context, listen: false).perApp.includedPackages),
    );
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.toLowerCase()));
    _loadApps();
  }

  Future<void> _loadApps() async {
    setState(() => _loading = true);
    try {
      final apps = await InstalledApps.getInstalledApps(true, true, '');
      apps.sort((a, b) {
        final aSel = _settings.includedPackages.contains(a.packageName);
        final bSel = _settings.includedPackages.contains(b.packageName);
        if (aSel && !bSel) return -1;
        if (!aSel && bSel) return 1;
        return a.name.compareTo(b.name);
      });
      if (mounted) setState(() { _apps = apps; _loading = false; });
    } catch (e, st) {
      // Список приложений не получен (нет разрешения/ошибка плагина) — снимаем
      // спиннер и фиксируем причину: иначе экран молча остаётся пустым.
      CrashLog.record(e, st, 'perapp.list');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _save() {
    AppStateScope.of(context, listen: false).setPerAppProxy(_settings);
  }

  // ── Пресеты ──────────────────────────────────────────────────────────────

  void _applyPreset(PerAppPreset p) {
    setState(() {
      _settings = PerAppProxySettings(
        enabled: true,
        includedPackages: List<String>.from(p.packages),
      );
    });
    _save();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Применён пресет «${p.name}»'), duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _saveCurrentAsPreset() async {
    if (_settings.includedPackages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала выберите приложения'), duration: Duration(seconds: 1)),
      );
      return;
    }
    final ctrl = TextEditingController();
    final t = IosTheme.of(context);
    final c = t.colors;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgSecondary,
        title: Text('Новый пресет', style: t.textStyles.headline),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          cursorColor: c.textPrimary,
          decoration: const InputDecoration(hintText: 'Название'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    if (!mounted) return;
    AppStateScope.of(context, listen: false).savePerAppPreset(
      PerAppPreset(name: name, packages: List<String>.from(_settings.includedPackages)),
    );
    if (mounted) setState(() {});
  }

  void _deletePreset(PerAppPreset p) {
    AppStateScope.of(context, listen: false).deletePerAppPreset(p.name);
    setState(() {});
  }

  List<AppInfo> get _filtered {
    if (_query.isEmpty) return _apps;
    return _apps.where((a) =>
      a.name.toLowerCase().contains(_query) ||
      a.packageName.toLowerCase().contains(_query)).toList();
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Widget _buildPresets(IosThemeData t, IosColors c) {
    final presets = AppStateScope.of(context).perAppPresets;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          children: [
            for (final p in presets)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _applyPreset(p),
                  onLongPress: p.builtin ? null : () => _confirmDeletePreset(p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: c.fill,
                      borderRadius: IosShapes.continuous(IosShapes.radiusField),
                    ),
                    child: Row(children: [
                      Icon(
                        p.builtin ? CupertinoIcons.square_stack_3d_up : CupertinoIcons.bookmark_fill,
                        size: 14, color: c.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(p.name, style: t.textStyles.footnote.copyWith(color: c.textPrimary)),
                    ]),
                  ),
                ),
              ),
            // Кнопка «сохранить текущий выбор как пресет»
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _saveCurrentAsPreset,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: c.bgSecondary,
                    borderRadius: IosShapes.continuous(IosShapes.radiusField),
                    border: Border.all(color: c.separator, width: 1),
                  ),
                  child: Row(children: [
                    Icon(CupertinoIcons.add, size: 14, color: c.blue),
                    const SizedBox(width: 6),
                    Text('Сохранить', style: t.textStyles.footnote.copyWith(color: c.blue)),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeletePreset(PerAppPreset p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить «${p.name}»?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok == true) _deletePreset(p);
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final filtered = _filtered;

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
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(children: [
              Expanded(child: Text('Прокси приложений', style: t.textStyles.largeTitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
              IosSwitch(
                value: _settings.enabled,
                onChanged: (v) { setState(() => _settings.enabled = v); _save(); },
              ),
            ]),
          ),

          // Info banner
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: IosCard(
              radius: IosShapes.radiusMedium,
              padding: const EdgeInsets.all(12),
              backgroundColor: _settings.enabled ? c.fill : c.bgSecondary,
              elevated: !_settings.enabled,
              child: Row(children: [
                Icon(
                  _settings.enabled ? CupertinoIcons.checkmark_alt_circle_fill : CupertinoIcons.info_circle,
                  size: 18,
                  color: _settings.enabled ? c.green : c.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  _settings.enabled
                    ? 'Только выбранные приложения идут через VPN. Остальные — напрямую.'
                    : 'Режим выключен. Включите, чтобы выбрать приложения.',
                  style: t.textStyles.footnote.copyWith(color: c.textSecondary),
                )),
              ]),
            ),
          ),

          // Presets
          _buildPresets(t, c),

          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: c.fill,
                borderRadius: IosShapes.continuous(IosShapes.radiusField),
              ),
              child: Row(children: [
                Icon(CupertinoIcons.search, size: 18, color: c.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    cursorColor: c.textPrimary,
                    style: t.textStyles.body,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Поиск приложений…',
                      hintStyle: t.textStyles.body.copyWith(color: c.textTertiary),
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ),
                if (_query.isNotEmpty)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () { _searchCtrl.clear(); },
                    child: Icon(CupertinoIcons.xmark_circle_fill, size: 18, color: c.textTertiary),
                  ),
              ]),
            ),
          ),

          // Counter
          if (_settings.includedPackages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(children: [
                Text(
                  'Выбрано: ${_settings.includedPackages.length}',
                  style: t.textStyles.footnote.copyWith(color: c.textSecondary),
                ),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () { setState(() => _settings.includedPackages.clear()); _save(); },
                  child: Text('Очистить', style: t.textStyles.footnote.copyWith(color: c.red)),
                ),
              ]),
            ),

          // List
          Expanded(
            child: _loading
              ? Center(child: CupertinoActivityIndicator(color: c.textPrimary))
              : filtered.isEmpty
                ? Center(child: Text('Ничего не найдено', style: t.textStyles.body.copyWith(color: c.textSecondary)))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    physics: const BouncingScrollPhysics(),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final app = filtered[i];
                      final selected = _settings.includedPackages.contains(app.packageName);
                      return IosCard(
                        radius: IosShapes.radiusMedium,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        elevated: false,
                        backgroundColor: c.bgSecondary,
                        onTap: () {
                          setState(() {
                            if (selected) {
                              _settings.includedPackages.remove(app.packageName);
                            } else {
                              _settings.includedPackages.add(app.packageName);
                            }
                          });
                          _save();
                        },
                        child: Row(children: [
                          // Иконка приложения
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: app.icon != null
                              ? Image.memory(app.icon!, width: 36, height: 36, fit: BoxFit.cover)
                              : Container(
                                  width: 36, height: 36,
                                  color: c.fill,
                                  child: Icon(CupertinoIcons.app, size: 18, color: c.textSecondary),
                                ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(app.name, style: t.textStyles.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text(app.packageName,
                                style: t.textStyles.caption2.copyWith(color: c.textTertiary),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            ]),
                          ),
                          // Checkbox в стиле iOS
                          Container(
                            width: 24, height: 24,
                            decoration: BoxDecoration(
                              color: selected ? c.textPrimary : Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(color: selected ? c.textPrimary : c.textTertiary, width: 1.5),
                            ),
                            child: selected
                              ? Icon(CupertinoIcons.check_mark, size: 14, color: c.bgSecondary)
                              : null,
                          ),
                        ]),
                      );
                    },
                  ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ]),
      ),
    );
  }
}

// lib/screens/log_screen.dart
//
// Экран просмотра VPN-лога (из HysteriaTunVpnService через bridge.getVpnLog()).

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ios_theme.dart';
import '../main.dart';
import '../logic/crash_log.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  String _log = 'Загрузка…';
  bool _loading = false;
  // false — нативный VPN-лог, true — Dart-краши из CrashLog
  bool _showCrashes = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_showCrashes) {
      // Dart-краши читаются синхронно из SharedPreferences.
      setState(() {
        _log = CrashLog.dump();
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    final state = AppStateScope.of(context);
    final log = await state.bridge.getVpnLog();
    if (!mounted) return;
    setState(() {
      _log = log;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    if (_showCrashes) {
      CrashLog.clear();
      await _refresh();
      return;
    }
    final state = AppStateScope.of(context);
    await state.bridge.clearVpnLog();
    await _refresh();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _log));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Лог скопирован'), duration: Duration(seconds: 1)),
    );
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
                      Text(' Настройки', style: t.textStyles.body.copyWith(color: c.textPrimary)),
                    ]),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _refresh,
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: c.fill, shape: BoxShape.circle),
                    child: Icon(CupertinoIcons.refresh, size: 18, color: c.textPrimary),
                  ),
                ),
              ]),
            ),

            // Title row
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(children: [
                Text(_showCrashes ? 'Dart-краши' : 'VPN-лог',
                    style: t.textStyles.largeTitle),
              ]),
            ),

            // Переключатель: нативный VPN-лог / Dart-краши приложения
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: CupertinoSlidingSegmentedControl<bool>(
                groupValue: _showCrashes,
                children: const {
                  false: Padding(
                    padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    child: Text('VPN-лог', style: TextStyle(fontSize: 13)),
                  ),
                  true: Padding(
                    padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    child: Text('Краши приложения', style: TextStyle(fontSize: 13)),
                  ),
                },
                onValueChanged: (v) {
                  if (v == null) return;
                  setState(() => _showCrashes = v);
                  _refresh();
                },
              ),
            ),

            // Log card
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: IosCard(
                  padding: const EdgeInsets.all(12),
                  radius: IosShapes.radiusLarge,
                  child: _loading
                      ? Center(child: CupertinoActivityIndicator(color: c.textPrimary))
                      : SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: SelectableText(
                            _log,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              height: 1.4,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                ),
              ),
            ),

            // Bottom buttons
            Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
              child: Row(children: [
                Expanded(
                  child: IosButton(
                    label: 'Копировать',
                    style: IosButtonStyle.secondary,
                    leadingIcon: CupertinoIcons.doc_on_clipboard,
                    onPressed: _copy,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: IosButton(
                    label: 'Очистить',
                    style: IosButtonStyle.destructive,
                    leadingIcon: CupertinoIcons.trash,
                    onPressed: _clear,
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

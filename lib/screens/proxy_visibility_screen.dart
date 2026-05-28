// lib/screens/proxy_visibility_screen.dart
//
// Проверка заметности наличия прокси:
//   - WebRTC утечка (раскрытие реального локального IP),
//   - TLS fingerprint (JA3/JA4) — насколько «нативно» выглядит handshake,
//   - HTTP-заголовки (Via/Forwarded/X-Forwarded-For),
//   - Расхождение часовых поясов / locale,
//   - Доступность типичных DPI-сайтов (если что-то блокирует — значит прокси
//     «прокалывается»).
//
// Это UI-каркас; чеки реализуются на стороне ядра/нативщины через bridge.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ios_theme.dart';
import '../main.dart';

class ProxyVisibilityScreen extends StatefulWidget {
  const ProxyVisibilityScreen({super.key});

  @override
  State<ProxyVisibilityScreen> createState() => _ProxyVisibilityScreenState();
}

class _ProxyVisibilityScreenState extends State<ProxyVisibilityScreen> {
  bool _running = false;
  final List<_Check> _checks = [
    _Check('webrtc',  'WebRTC утечка',          'Раскрытие локального IP через STUN'),
    _Check('tls_fp',  'TLS fingerprint',         'JA3/JA4 совпадает с типичным браузером'),
    _Check('headers', 'HTTP-заголовки',          'Via / Forwarded / X-Forwarded-For'),
    _Check('tz',      'Расхождение TZ/locale',   'Часовой пояс системы vs геолокация'),
    _Check('dpi',     'DPI-зонды',               'Доступность типовых заблокированных хостов'),
    _Check('ipv6',    'IPv6 утечка',             'IPv6-резолв в обход VPN'),
  ];
  int? _score; // 0..100

  Future<void> _run() async {
    setState(() {
      _running = true;
      _score = null;
      for (final ch in _checks) {
        ch.state = _CheckState.running;
        ch.detail = '';
      }
    });

    final bridge = AppStateScope.of(context, listen: false).bridge;
    final raw = await bridge.runProxyVisibilityCheck();
    final byId = <String, Map<String, dynamic>>{
      for (final m in raw) (m['id'] as String? ?? ''): m,
    };

    if (!mounted) return;
    setState(() {
      int okCount = 0;
      for (final ch in _checks) {
        final m = byId[ch.id];
        if (m == null) {
          ch.state = _CheckState.warn;
          ch.detail = 'Нет ответа от ядра';
          continue;
        }
        final ok = (m['ok'] as bool?) ?? false;
        ch.state = ok ? _CheckState.ok : _CheckState.warn;
        ch.detail = (m['detail'] as String?) ??
            (ok ? 'Не обнаружено признаков прокси' : 'Обнаружен индикатор');
        if (ok) okCount++;
      }
      _score = _checks.isEmpty
          ? 0
          : ((okCount / _checks.length) * 100).round();
      _running = false;
    });
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
            const SliverToBoxAdapter(child: _ScreenHeader(title: 'Заметность прокси')),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Серия проверок, помогающих понять, насколько ваше '
                  'соединение «выглядит как прокси» для типового веб-сайта или '
                  'DPI-системы. Чем выше итоговый балл — тем незаметнее.',
                  style: t.textStyles.subheadline.copyWith(color: c.textSecondary),
                ),
              ),
            ),

            // Кнопка + балл
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: c.bgSecondary,
                    borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
                  ),
                  child: Column(children: [
                    if (_score != null) ...[
                      Text('$_score', style: t.textStyles.largeTitle.copyWith(
                        fontSize: 56,
                        color: _score! >= 80 ? c.green : (_score! >= 50 ? c.orange : c.red),
                      )),
                      Text('из 100', style: t.textStyles.footnote.copyWith(color: c.textSecondary)),
                      const SizedBox(height: 12),
                    ] else if (!_running) ...[
                      Icon(CupertinoIcons.eye, size: 48, color: c.textSecondary),
                      const SizedBox(height: 12),
                      Text('Готов к проверке', style: t.textStyles.headline),
                      const SizedBox(height: 12),
                    ] else ...[
                      const SizedBox(height: 8),
                      const CircularProgressIndicator(strokeWidth: 2.5),
                      const SizedBox(height: 12),
                      Text('Идёт проверка...', style: t.textStyles.headline),
                      const SizedBox(height: 12),
                    ],
                    IosButton(
                      label: _running
                          ? 'Подождите...'
                          : (_score == null ? 'Запустить проверку' : 'Прогнать заново'),
                      style: IosButtonStyle.primary,
                      onPressed: _running ? null : _run,
                    ),
                  ]),
                ),
              ),
            ),

            // Чеки
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Проверки',
                children: [
                  for (final ch in _checks)
                    IosListTile(
                      leadingIcon: _iconFor(ch.state),
                      leadingIconBg: _bgFor(ch.state, c),
                      title: ch.title,
                      subtitle: ch.detail.isEmpty ? ch.hint : ch.detail,
                    ),
                ],
              ),
            ),

            SliverToBoxAdapter(
              child: SizedBox(height: MediaQuery.of(context).padding.bottom + 32),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(_CheckState s) {
    switch (s) {
      case _CheckState.idle:    return CupertinoIcons.circle;
      case _CheckState.pending: return CupertinoIcons.clock;
      case _CheckState.running: return CupertinoIcons.ellipsis;
      case _CheckState.ok:      return CupertinoIcons.checkmark_alt_circle_fill;
      case _CheckState.warn:    return CupertinoIcons.exclamationmark_triangle_fill;
    }
  }

  Color _bgFor(_CheckState s, IosColors c) {
    switch (s) {
      case _CheckState.idle:
      case _CheckState.pending: return c.fill;
      case _CheckState.running: return c.blue;
      case _CheckState.ok:      return c.green;
      case _CheckState.warn:    return c.red;
    }
  }
}

enum _CheckState { idle, pending, running, ok, warn }

class _Check {
  final String id;
  final String title;
  final String hint;
  _CheckState state = _CheckState.idle;
  String detail = '';
  _Check(this.id, this.title, this.hint);
}

class _ScreenHeader extends StatelessWidget {
  final String title;
  const _ScreenHeader({required this.title});

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
          Text(title, style: t.textStyles.title3),
          const Spacer(),
        ],
      ),
    );
  }
}

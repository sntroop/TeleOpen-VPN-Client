import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ios_theme.dart';
import '../main.dart';

class DnsLeakTestScreen extends StatefulWidget {
  const DnsLeakTestScreen({super.key});

  @override
  State<DnsLeakTestScreen> createState() => _DnsLeakTestScreenState();
}

class _DnsLeakTestScreenState extends State<DnsLeakTestScreen> {
  bool _running = false;
  String _status = 'Готов к тесту';
  final List<_ResolverInfo> _resolvers = [];

  
  
  List<String> _buildCanaryNames() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return List.generate(6, (i) => 't$ts$i.test.dnsleaktest.local');
  }

  Future<void> _runTest() async {
    setState(() {
      _running = true;
      _status = 'Опрашиваем резолверы...';
      _resolvers.clear();
    });

    final bridge = AppStateScope.of(context, listen: false).bridge;
    final raw = await bridge.runDnsLeakTest();

    if (!mounted) return;
    final parsed = raw.map((m) {
      return _ResolverInfo(
        ip: (m['ip'] as String?) ?? '?',
        org: (m['org'] as String?) ?? 'Unknown',
        country: (m['country'] as String?) ?? '??',
        isLeak: (m['leak'] as bool?) ?? false,
      );
    }).toList();

    setState(() {
      _resolvers.addAll(parsed);
      if (parsed.isEmpty) {
        _status = 'Не удалось получить ответ - проверьте VPN и попробуйте снова';
      } else {
        _status = parsed.any((r) => r.isLeak)
            ? 'Обнаружена утечка!'
            : 'Утечки не обнаружено';
      }
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final hasLeak = _resolvers.any((r) => r.isLeak);

    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _ScreenHeader(title: 'Тест утечки DNS')),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Резолвим несколько уникальных доменов и смотрим, какие '
                  'DNS-серверы получили запрос. Если в списке оказывается '
                  'резолвер вашего провайдера или Wi-Fi-сети - DNS «утекает» '
                  'мимо VPN.',
                  style: t.textStyles.subheadline.copyWith(color: c.textSecondary),
                ),
              ),
            ),

            
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
                    Icon(
                      _running
                          ? CupertinoIcons.ellipsis
                          : (_resolvers.isEmpty
                              ? CupertinoIcons.question_circle
                              : hasLeak
                                  ? CupertinoIcons.exclamationmark_triangle_fill
                                  : CupertinoIcons.checkmark_seal_fill),
                      size: 48,
                      color: _running
                          ? c.textSecondary
                          : (_resolvers.isEmpty
                              ? c.textSecondary
                              : hasLeak ? c.red : c.green),
                    ),
                    const SizedBox(height: 12),
                    Text(_status, style: t.textStyles.headline, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    IosButton(
                      label: _running ? 'Идёт тест...' : (_resolvers.isEmpty ? 'Запустить тест' : 'Прогнать заново'),
                      style: IosButtonStyle.primary,
                      onPressed: _running ? null : _runTest,
                    ),
                  ]),
                ),
              ),
            ),

            
            if (_resolvers.isNotEmpty)
              SliverToBoxAdapter(
                child: IosListSection(
                  header: 'Обнаруженные резолверы',
                  children: [
                    for (final r in _resolvers)
                      IosListTile(
                        leadingIcon: r.isLeak
                            ? CupertinoIcons.exclamationmark_circle_fill
                            : CupertinoIcons.checkmark_alt_circle_fill,
                        leadingIconBg: r.isLeak ? c.red : c.green,
                        title: r.ip,
                        subtitle: '${r.org} · ${r.country}',
                        trailingText: r.isLeak ? 'УТЕЧКА' : 'OK',
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
}

class _ResolverInfo {
  final String ip;
  final String org;
  final String country;
  final bool isLeak;
  _ResolverInfo({required this.ip, required this.org, required this.country, required this.isLeak});
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

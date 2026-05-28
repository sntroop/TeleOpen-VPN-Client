import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ios_theme.dart';
import '../main.dart';

class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key});

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final s = AppStateScope.of(context).settings;

    void update(void Function(AppSettings s) mutate) {
      mutate(s);
      AppStateScope.of(context, listen: false).updateSettings(s);
    }

    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _ScreenHeader(title: 'Сеть')),

            SliverToBoxAdapter(
              child: IosListSection(
                children: [
                  _toggle(
                    icon: CupertinoIcons.globe,
                    bg: c.blue,
                    title: 'Маршрутизировать системный трафик',
                    subtitle: 'Весь трафик идёт через VPN',
                    value: s.netRouteSystemTraffic,
                    onChanged: (v) => update((x) => x.netRouteSystemTraffic = v),
                  ),
                  _toggle(
                    icon: CupertinoIcons.house,
                    bg: c.fill,
                    title: 'Игнорировать частные сети',
                    subtitle: 'Адреса 10.x / 192.168.x не маршрутизируются',
                    value: s.netBypassPrivate,
                    onChanged: (v) => update((x) => x.netBypassPrivate = v),
                  ),
                  _toggle(
                    icon: CupertinoIcons.bolt,
                    bg: c.fill,
                    title: 'Перехват DNS',
                    subtitle: 'Обрабатывать все DNS-запросы',
                    value: s.netHijackDns,
                    onChanged: (v) => update((x) => x.netHijackDns = v),
                  ),
                  _toggle(
                    icon: CupertinoIcons.arrow_turn_down_right,
                    bg: c.fill,
                    title: 'Разрешить обход',
                    subtitle: 'Приложения могут обходить VPN-соединение',
                    value: s.netAllowBypass,
                    onChanged: (v) => update((x) => x.netAllowBypass = v),
                  ),
                  _toggle(
                    icon: CupertinoIcons.number_circle,
                    bg: c.fill,
                    title: 'Allow IPv6',
                    subtitle: 'Трафик IPv6 через VpnService',
                    value: s.netAllowIpv6,
                    onChanged: (v) => update((x) => x.netAllowIpv6 = v),
                  ),
                  _toggle(
                    icon: CupertinoIcons.dot_radiowaves_left_right,
                    bg: c.fill,
                    title: 'Системный прокси',
                    subtitle: 'Запустить HTTP-прокси помимо VPN',
                    value: s.netSystemProxy,
                    onChanged: (v) => update((x) => x.netSystemProxy = v),
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

  Widget _toggle({
    required IconData icon,
    required Color bg,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return IosListTile(
      leadingIcon: icon,
      leadingIconBg: bg,
      title: title,
      subtitle: subtitle,
      trailing: IosSwitch(value: value, onChanged: onChanged),
    );
  }
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

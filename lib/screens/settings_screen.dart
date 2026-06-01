// lib/screens/settings_screen.dart
//
// Экран настроек в стиле iOS Settings.app.
// Все переключатели и пикеры читают начальные значения из AppSettings
// и сохраняют изменения через AppState.updateSettings() → SharedPreferences.

library settings_screen;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ios_theme.dart';
import '../main.dart';
import 'log_screen.dart';
import 'world_map_screen.dart';
import 'per_app_proxy_screen.dart';
import 'dns_screen.dart';
// import 'warp_screen.dart'; // WARP скрыт до реализации (см. ниже)
import 'tls_tricks_screen.dart';
import 'diagnostics_screen.dart';
import 'author_panel_screen.dart';
import 'admin_panel_screen.dart';
import 'themes_screen.dart';
import 'network_screen.dart';
import 'meta_features_screen.dart';
import 'dns_leak_test_screen.dart';
import 'proxy_visibility_screen.dart';
import 'statistics_screen.dart';
import 'fix_server_screen.dart';
import 'privacy_screen.dart';

part 'settings/parts.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Локальная копия настроек — инициализируется из AppState в initState.
  late AppSettings _s;

  // Версия приложения, читается из нативки (канал space.teleopen.app/native).
  String _appVersion = '';

  static const _ipv6Modes = <String>[
    'Отключить',
    'Только IPv4',
    'Предпочитать IPv4',
    'Предпочитать IPv6',
    'Только IPv6',
  ];

  static const _regions = <String>[
    'Россия (ru)',
    'США (us)',
    'Германия (de)',
    'Нидерланды (nl)',
    'Великобритания (gb)',
    'Япония (jp)',
    'Сингапур (sg)',
  ];

  @override
  void initState() {
    super.initState();
    // Читаем актуальные настройки из AppState при открытии экрана.
    final appSettings = AppStateScope.of(context, listen: false).settings;
    _s = AppSettings(
      killSwitch:         appSettings.killSwitch,
      autoConnect:        appSettings.autoConnect,
      autoFailover:       appSettings.autoFailover,
      dns:                appSettings.dns,
      packetAnalysis:     appSettings.packetAnalysis,
      useMux:             appSettings.useMux,
      region:             appSettings.region,
      balancerStrategy:   appSettings.balancerStrategy,
      blockAds:           appSettings.blockAds,
      bypassLan:          appSettings.bypassLan,
      resolveDestination: appSettings.resolveDestination,
      ipv6Route:          appSettings.ipv6Route,
    );
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      const channel = MethodChannel('space.teleopen.app/native');
      final name = await channel.invokeMethod<String>('getAppVersionName');
      final code = await channel.invokeMethod<int>('getAppVersionCode');
      if (!mounted) return;
      setState(() {
        _appVersion = [
          if (name != null && name.isNotEmpty) name,
          if (code != null) '($code)',
        ].join(' ');
      });
    } catch (_) {
      // нативка недоступна (напр. тесты) — оставляем пусто
    }
  }

  /// Применяет локальное изменение и сохраняет в AppState + SharedPreferences.
  void _update(void Function(AppSettings s) mutate) {
    setState(() => mutate(_s));
    AppStateScope.of(context, listen: false).updateSettings(_s);
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final state = AppStateScope.of(context);

    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Шапка ───────────────────────────────────────────────────
            SliverToBoxAdapter(child: _SettingsHeader()),

            // ── ПОЧИНИТЬ СЕРВЕР (ИИ-диагностика) ────────────────────────
            SliverToBoxAdapter(
              child: IosListSection(
                children: [
                  IosListTile(
                    leadingIcon: CupertinoIcons.wand_stars,
                    leadingIconBg: c.blue,
                    title: 'Починить сервер',
                    subtitle: 'ИИ сам подберёт настройки',
                    showChevron: true,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const FixServerScreen(),
                    )),
                  ),
                ],
              ),
            ),

            // ── СОЕДИНЕНИЕ ──────────────────────────────────────────────
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Соединение',
                children: [
                  IosListTile(
                    leadingIcon: CupertinoIcons.shield_lefthalf_fill,
                    leadingIconBg: c.green,
                    title: 'Kill Switch',
                    subtitle: 'Блокировать интернет при разрыве VPN',
                    trailing: IosSwitch(
                      value: _s.killSwitch,
                      onChanged: (v) => _update((s) => s.killSwitch = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.bolt_fill,
                    leadingIconBg: c.orange,
                    title: 'Автоподключение',
                    subtitle: 'Подключаться при запуске',
                    trailing: IosSwitch(
                      value: _s.autoConnect,
                      onChanged: (v) => _update((s) => s.autoConnect = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.arrow_2_circlepath,
                    leadingIconBg: c.blue,
                    title: 'Авто-переключение сервера',
                    subtitle: 'Сменить сервер, если текущий не отвечает',
                    trailing: IosSwitch(
                      value: _s.autoFailover,
                      onChanged: (v) => _update((s) => s.autoFailover = v),
                    ),
                  ),
                  // DNS-сервер (главный): скрыт — конфликтует с моделью
                  // remote/direct DNS (экран «Сеть → DNS»), ядро xray этот
                  // одиночный ключ не читает. Настройка DNS — на экране DNS.
                  // IosListTile(
                  //   leadingIcon: CupertinoIcons.globe,
                  //   leadingIconBg: c.fill,
                  //   title: 'DNS-сервер',
                  //   trailingText: _s.dns,
                  //   showChevron: true,
                  //   onTap: () => _showDnsPicker(context),
                  // ),
                ],
              ),
            ),

            // ── ПРОДВИНУТОЕ ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Продвинутое',
                children: [
                  IosListTile(
                    leadingIcon: CupertinoIcons.chart_bar_alt_fill,
                    leadingIconBg: c.purple,
                    title: 'Анализ пакетов',
                    subtitle: 'Sniffing для HTTP/TLS',
                    trailing: IosSwitch(
                      value: _s.packetAnalysis,
                      onChanged: (v) => _update((s) => s.packetAnalysis = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.arrow_branch,
                    leadingIconBg: c.fill,
                    title: 'Mux (мультиплексирование)',
                    subtitle: 'Несколько соединений в одном',
                    trailing: IosSwitch(
                      value: _s.useMux,
                      onChanged: (v) => _update((s) => s.useMux = v),
                    ),
                  ),
                ],
              ),
            ),

            // ── МАРШРУТИЗАЦИЯ ────────────────────────────────────────────
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Маршрутизация',
                children: [
                  IosListTile(
                    leadingIcon: CupertinoIcons.square_grid_2x2,
                    leadingIconBg: c.fill,
                    title: 'Прокси для приложений',
                    trailing: IosSwitch(
                      value: AppStateScope.of(context).perApp.enabled,
                      onChanged: (v) {
                        AppStateScope.of(context, listen: false).setPerAppProxy(
                          AppStateScope.of(context, listen: false).perApp.copyWith(enabled: v),
                        );
                        if (v) {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const PerAppProxyScreen(),
                          ));
                        }
                      },
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.placemark_fill,
                    leadingIconBg: c.fill,
                    title: 'Регион',
                    subtitle: _s.region,
                    showChevron: true,
                    onTap: () => _showOptions(
                      title: 'Регион',
                      options: _regions,
                      current: _s.region,
                      onSelect: (v) => _update((s) => s.region = v),
                    ),
                  ),
                  // Стратегия Balancer: скрыта — балансировка требует нескольких
                  // outbound'ов, а у нас single-node (один активный сервер).
                  // Включить вместе с мульти-узловым outbound'ом в будущем.
                  // IosListTile(
                  //   leadingIcon: CupertinoIcons.arrow_2_squarepath,
                  //   leadingIconBg: c.fill,
                  //   title: 'Стратегия Balancer',
                  //   subtitle: _s.balancerStrategy,
                  //   showChevron: true,
                  //   onTap: () => _showOptions(
                  //     title: 'Стратегия Balancer',
                  //     options: _balancerStrategies,
                  //     current: _s.balancerStrategy,
                  //     onSelect: (v) => _update((s) => s.balancerStrategy = v),
                  //   ),
                  // ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.nosign,
                    leadingIconBg: c.fill,
                    title: 'Блокировать рекламу',
                    trailing: IosSwitch(
                      value: _s.blockAds,
                      onChanged: (v) => _update((s) => s.blockAds = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.arrow_branch,
                    leadingIconBg: c.fill,
                    title: 'Обход LAN',
                    trailing: IosSwitch(
                      value: _s.bypassLan,
                      onChanged: (v) => _update((s) => s.bypassLan = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.shield,
                    leadingIconBg: c.fill,
                    title: 'Определять адрес назначения',
                    trailing: IosSwitch(
                      value: _s.resolveDestination,
                      onChanged: (v) => _update((s) => s.resolveDestination = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.number,
                    leadingIconBg: c.fill,
                    title: 'Маршрут IPv6',
                    subtitle: _s.ipv6Route,
                    showChevron: true,
                    onTap: () => _showOptions(
                      title: 'Маршрут IPv6',
                      options: _ipv6Modes,
                      current: _s.ipv6Route,
                      onSelect: (v) => _update((s) => s.ipv6Route = v),
                    ),
                  ),
                ],
              ),
            ),

            // ── СЕТЬ (DNS / WARP / TLS) ──────────────────────────────────
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Сеть',
                children: [
                  IosListTile(
                    leadingIcon: CupertinoIcons.globe,
                    leadingIconBg: c.blue,
                    title: 'DNS',
                    subtitle: 'Удаленный и исходящий DNS',
                    showChevron: true,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const DnsScreen(),
                    )),
                  ),
                  // WARP скрыт до реализации нативной генерации конфигурации
                  // (см. warp_screen.dart _generateConfig — пока no-op).
                  // Не показываем мёртвую кнопку в проде.
                  // IosListTile(
                  //   leadingIcon: CupertinoIcons.cloud,
                  //   leadingIconBg: c.orange,
                  //   title: 'WARP',
                  //   subtitle: 'Cloudflare WARP и шум',
                  //   showChevron: true,
                  //   onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  //     builder: (_) => const WarpScreen(),
                  //   )),
                  // ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.scissors,
                    leadingIconBg: c.purple,
                    title: 'Трюки TLS',
                    subtitle: 'Фрагментация, SNI, padding',
                    showChevron: true,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const TlsTricksScreen(),
                    )),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.map,
                    leadingIconBg: c.fill,
                    title: 'Карта серверов',
                    subtitle: 'Визуализация на карте мира',
                    showChevron: true,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const WorldMapScreen(),
                    )),
                  ),
                ],
              ),
            ),

            // ── ПРОДВИНУТАЯ СЕТЬ ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Продвинутая сеть',
                footer:
                    'Тонкая настройка ядра: интеграция с системой, локальные '
                    'порты прокси, REST-API контроллера и расширения Mihomo/Meta.',
                children: [
                  IosListTile(
                    leadingIcon: CupertinoIcons.antenna_radiowaves_left_right,
                    leadingIconBg: c.blue,
                    title: 'Сеть',
                    subtitle: 'Маршрутизация, DNS-перехват, IPv6',
                    showChevron: true,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const NetworkScreen(),
                    )),
                  ),
                  // Локальные порты и External Controller скрыты: приложение
                  // намеренно не поднимает socks/http-inbound (весь трафик через
                  // TUN, см. parsers.dart buildXrayConfig) и не запускает REST-API
                  // ядра. Эти настройки ни на что не влияли бы.
                  // IosListTile(
                  //   leadingIcon: CupertinoIcons.number,
                  //   leadingIconBg: c.fill,
                  //   title: 'Локальные порты',
                  //   subtitle: 'HTTP/Socks/TProxy/Mixed, LAN, Bind',
                  //   showChevron: true,
                  //   onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  //     builder: (_) => const LocalPortsScreen(),
                  //   )),
                  // ),
                  // IosListTile(
                  //   leadingIcon: CupertinoIcons.lock_circle,
                  //   leadingIconBg: c.fill,
                  //   title: 'External Controller',
                  //   subtitle: 'REST-API для дашбордов',
                  //   showChevron: true,
                  //   onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  //     builder: (_) => const ExternalControllerScreen(),
                  //   )),
                  // ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.gear_alt_fill,
                    leadingIconBg: c.purple,
                    title: 'Функции Meta',
                    subtitle: 'Sniffing, Geo Files, MPTCP',
                    showChevron: true,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const MetaFeaturesScreen(),
                    )),
                  ),
                ],
              ),
            ),

            // ── ДИАГНОСТИКА ──────────────────────────────────────────────
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Диагностика',
                children: [
                  IosListTile(
                    leadingIcon: CupertinoIcons.chart_bar_fill,
                    leadingIconBg: c.blue,
                    title: 'Статистика',
                    subtitle: 'Трафик, сессии, топ серверов',
                    showChevron: true,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const StatisticsScreen(),
                    )),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.doc_text_search,
                    leadingIconBg: c.fill,
                    title: 'VPN-лог',
                    subtitle: 'Журнал работы движка',
                    showChevron: true,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const LogScreen(),
                    )),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.wand_stars,
                    leadingIconBg: c.yellow,
                    title: 'Диагностика сети',
                    subtitle: 'Проверить доступность',
                    showChevron: true,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const DiagnosticsScreen(),
                    )),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.drop_triangle,
                    leadingIconBg: c.red,
                    title: 'Тест утечки DNS',
                    subtitle: 'Проверить, не утекают ли запросы',
                    showChevron: true,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const DnsLeakTestScreen(),
                    )),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.eye,
                    leadingIconBg: c.fill,
                    title: 'Заметность прокси',
                    subtitle: 'WebRTC, JA3, заголовки',
                    showChevron: true,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ProxyVisibilityScreen(),
                    )),
                  ),
                ],
              ),
            ),

            // ── О ПРИЛОЖЕНИИ ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'О приложении',
                children: [
                  IosListTile(
                    leadingIcon: CupertinoIcons.info,
                    leadingIconBg: c.fill,
                    title: 'Версия',
                    trailingText: _appVersion.isEmpty ? '—' : _appVersion,
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.lock_shield_fill,
                    leadingIconBg: c.blue,
                    title: 'Безопасность',
                    showChevron: true,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const PrivacyScreen(),
                    )),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.person_2_fill,
                    leadingIconBg: c.pink,
                    title: 'Авторы',
                    showChevron: true,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AuthorPanelScreen(),
                    )),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.paintbrush_fill,
                    leadingIconBg: c.purple,
                    title: 'Темы оформления',
                    showChevron: true,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ThemesScreen(),
                    )),
                  ),
                  if (state.currentUser?.isAdmin == true)
                    IosListTile(
                      leadingIcon: CupertinoIcons.shield_fill,
                      leadingIconBg: c.red,
                      title: 'Модерация',
                      showChevron: true,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const AdminPanelScreen(),
                      )),
                    ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.heart_fill,
                    leadingIconBg: c.red,
                    title: 'Поддержать',
                    showChevron: true,
                    onTap: () => _showSupport(context),
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

  // ─── Picker: универсальный выбор из списка ───────────────────────────────
  void _showOptions({
    required String title,
    required List<String> options,
    required String current,
    required ValueChanged<String> onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _OptionPickerSheet(
        title: title,
        options: options,
        currentValue: current,
        onSelect: onSelect,
      ),
    );
  }

  // ─── Диалог «Поддержать» ────────────────────────────────────────────────
  void _showSupport(BuildContext context) {
    IosDialog.show(
      context,
      IosDialog(
        title: 'Поддержать проект',
        description: 'Если приложение вам полезно — расскажите о нём друзьям или оставьте отзыв в магазине.',
        actions: [
          IosButton(
            label: 'Закрыть',
            style: IosButtonStyle.plain,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// HEADER
// ════════════════════════════════════════════════════════════════════════════


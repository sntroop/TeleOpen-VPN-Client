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
import 'byedpi_screen.dart';
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
import 'routing_rules_screen.dart';
import 'share_screen.dart';
import 'seller_cabinet_screen.dart';
import 'proxy_auth_screen.dart'; // NEW
import 'excluded_routes_screen.dart'; // NEW
import '../logic/market_api.dart';

part 'settings/parts.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Локальная копия настроек — инициализируется из AppState в initState.
  late AppSettings _s;

  // Скролл + флаг показа плавающей кнопки «Назад» (когда шапка уехала вверх).
  final ScrollController _scrollCtrl = ScrollController();
  bool _showBackPill = false;

  // Версия приложения, читается из нативки (канал space.teleopen.app/native).
  String _appVersion = '';

  // Внутренний (покупательский) баланс юзера — выдаётся админом, тратится на
  // покупки в маркете. null = ещё не загружен или юзер не залогинен.
  double? _balance;

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
    // Полная копия (а не частичный конструктор): иначе сохранение из этого
    // экрана затёрло бы поля, которые правятся на других экранах (DNS, Meta,
    // ByeDPI) — updateSettings() пишет в prefs ВЕСЬ объект.
    final appSettings = AppStateScope.of(context, listen: false).settings;
    _s = AppSettings.copy(appSettings);
    _scrollCtrl.addListener(_onScroll);
    _loadVersion();
    _loadBalance();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Шапка с «Назад» ~50px высотой — после неё показываем плавающую кнопку.
    final show = _scrollCtrl.offset > 50;
    if (show != _showBackPill) setState(() => _showBackPill = show);
  }

  /// Покупательский баланс — только для залогиненных. Ошибки глушим: это
  /// необязательная плитка, без неё настройки работают как раньше.
  Future<void> _loadBalance() async {
    if (AppStateScope.of(context, listen: false).currentUser == null) return;
    try {
      final bal = await MarketApi.myBalance();
      if (!mounted) return;
      setState(() => _balance = bal);
    } catch (_) {
      // нет сети / не залогинен — просто не показываем плитку
    }
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
        child: Stack(
          children: [
            CustomScrollView(
              controller: _scrollCtrl,
              physics: const BouncingScrollPhysics(),
              slivers: [
                // ── Шапка ───────────────────────────────────────────────────
                SliverToBoxAdapter(child: _SettingsHeader()),

                // ── ОФОРМЛЕНИЕ ──────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: IosListSection(
                    children: [
                      IosListTile(
                        leadingIcon: CupertinoIcons.paintbrush_fill,
                        leadingIconBg: c.purple,
                        title: 'Темы оформления',
                        subtitle: 'Цвета, радиусы и иконка приложения',
                        showChevron: true,
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const ThemesScreen(),
                        )),
                      ),
                    ],
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // ── СОЗДАТЬ ПОДПИСКУ (поделиться своими серверами) ──────────
                SliverToBoxAdapter(
                  child: IosListSection(
                    children: [
                      if (_balance != null && _balance! > 0)
                        IosListTile(
                          leadingIcon: CupertinoIcons.creditcard_fill,
                          leadingIconBg: c.green,
                          title: 'Мой баланс',
                          subtitle: 'Можно оплатить покупки в маркете',
                          trailingText: _balance! == _balance!.roundToDouble()
                              ? '${_balance!.toInt()} ₽'
                              : '${_balance!.toStringAsFixed(2)} ₽',
                        ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.square_arrow_up,
                        leadingIconBg: c.purple,
                        title: 'Создать подписку',
                        subtitle: 'Собрать свои серверы в одну ссылку',
                        showChevron: true,
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const ShareScreen(),
                        )),
                      ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.bag_fill,
                        leadingIconBg: c.green,
                        title: 'Кабинет продавца',
                        subtitle: 'Продажа подписок, баланс, вывод средств',
                        showChevron: true,
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const SellerCabinetScreen(),
                        )),
                      ),
                    ],
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 12)),

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
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
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
                        leadingIcon: CupertinoIcons.device_phone_portrait,
                        leadingIconBg: c.blue,
                        title: 'Автозапуск при загрузке',
                        subtitle: 'Подключаться при включении устройства',
                        trailing: IosSwitch(
                          value: _s.autoConnectOnBoot,
                          onChanged: (v) => _update((s) => s.autoConnectOnBoot = v),
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
                        leadingIcon: CupertinoIcons.rectangle_stack_fill,
                        leadingIconBg: c.blue,
                        title: 'Режим туннеля',
                        subtitle: _tunnelModeSubtitle(_s.tunnelMode),
                        showChevron: true,
                        onTap: () => _showTunnelModePicker(),
                      ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.layers_alt_fill,
                        leadingIconBg: c.red,
                        title: 'Режим xray-TUN',
                        subtitle: 'Xray управляет TUN напрямую (меньше RAM)',
                        trailing: IosSwitch(
                          value: _s.xrayTunMode,
                          onChanged: (v) => _update((s) => s.xrayTunMode = v),
                        ),
                      ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.sun_max_fill,
                        leadingIconBg: c.orange,
                        title: 'Держать устройство активным',
                        subtitle: 'Wakelock для Xiaomi/HyperOS',
                        trailing: IosSwitch(
                          value: _s.keepDeviceAwake,
                          onChanged: (v) => _update((s) => s.keepDeviceAwake = v),
                        ),
                      ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.gauge,
                        leadingIconBg: c.purple,
                        title: 'Лимит памяти',
                        subtitle: _memoryLimitSubtitle(_s.memoryLimitMB),
                        showChevron: true,
                        onTap: () => _showMemoryLimitPicker(),
                      ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.wifi,
                        leadingIconBg: c.green,
                        title: 'LAN через прокси',
                        subtitle: 'Форсировать локальный трафик через прокси',
                        trailing: IosSwitch(
                          value: _s.routeLanThroughProxy,
                          onChanged: (v) => _update((s) => s.routeLanThroughProxy = v),
                        ),
                      ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.bolt_horizontal_fill,
                        leadingIconBg: c.orange,
                        title: 'Тип IP',
                        subtitle: _ipTypeSubtitle(_s.ipType),
                        showChevron: true,
                        onTap: () => _showIpTypePicker(),
                      ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.nosign,
                        leadingIconBg: c.red,
                        title: 'Блокировать UDP',
                        subtitle: 'Ломает QUIC, DoH-UDP, звонки, игры',
                        trailing: IosSwitch(
                          value: _s.blockUdp,
                          onChanged: (v) => _update((s) => s.blockUdp = v),
                        ),
                      ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.speedometer,
                        leadingIconBg: c.green,
                        title: 'Скорость в уведомлении',
                        subtitle: 'Показывать ↓/↑ в шторке',
                        trailing: IosSwitch(
                          value: _s.showSpeedInNotification,
                          onChanged: (v) =>
                              _update((s) => s.showSpeedInNotification = v),
                        ),
                      ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.chart_bar_alt_fill,
                        leadingIconBg: c.purple,
                        title: 'Анализ пакетов',
                        subtitle: 'Sniffing для HTTP/TLS',
                        trailing: IosSwitch(
                          value: _s.packetAnalysis,
                          onChanged: (v) =>
                              _update((s) => s.packetAnalysis = v),
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
                      IosListTile(
                        leadingIcon: CupertinoIcons.speedometer,
                        leadingIconBg: c.fill,
                        title: 'Тип пинга',
                        subtitle: _pingModeSubtitle(_s.pingMode),
                        showChevron: true,
                        onTap: () => _showOptions(
                          title: 'Тип пинга',
                          options: kPingModes,
                          current: _s.pingMode,
                          onSelect: (v) => _update((s) => s.pingMode = v),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── СОЕДИНЕНИЯ И ЛОГИ ────────────────────────────────────────
                SliverToBoxAdapter(
                  child: IosListSection(
                    header: 'Соединения и логи',
                    children: [
                      IosListTile(
                        leadingIcon: CupertinoIcons.timer,
                        leadingIconBg: c.blue,
                        title: 'Таймаут простоя',
                        subtitle: '${_s.connIdleTimeout} сек',
                        showChevron: true,
                        onTap: () => _showIntPicker(
                          title: 'Таймаут простоя',
                          options: const [60, 120, 180, 300, 600, 900],
                          current: _s.connIdleTimeout,
                          suffix: ' сек',
                          onSelect: (v) => _update((s) => s.connIdleTimeout = v),
                        ),
                      ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.arrow_up_arrow_down,
                        leadingIconBg: c.green,
                        title: 'TCP соединения',
                        subtitle: 'Максимум одновременных: ${_s.maxTcpConns}',
                        showChevron: true,
                        onTap: () => _showIntPicker(
                          title: 'TCP соединения',
                          options: const [64, 128, 256, 512, 1024],
                          current: _s.maxTcpConns,
                          onSelect: (v) => _update((s) => s.maxTcpConns = v),
                        ),
                      ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.arrow_up_arrow_down,
                        leadingIconBg: c.orange,
                        title: 'UDP соединения',
                        subtitle: 'Максимум одновременных: ${_s.maxUdpConns}',
                        showChevron: true,
                        onTap: () => _showIntPicker(
                          title: 'UDP соединения',
                          options: const [32, 64, 128, 256, 512],
                          current: _s.maxUdpConns,
                          onSelect: (v) => _update((s) => s.maxUdpConns = v),
                        ),
                      ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.arrow_branch,
                        leadingIconBg: c.purple,
                        title: 'Исключённые маршруты',
                        subtitle: '${_s.excludedRoutes.length} подсетей мимо туннеля',
                        showChevron: true,
                        onTap: () => _openExcludedRoutesEditor(),
                      ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.doc_text,
                        leadingIconBg: c.red,
                        title: 'Хранение логов',
                        subtitle: _logRetentionSubtitle(_s.logRetention),
                        showChevron: true,
                        onTap: () => _showLogRetentionPicker(),
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
                            AppStateScope.of(context, listen: false)
                                .setPerAppProxy(
                              AppStateScope.of(context, listen: false)
                                  .perApp
                                  .copyWith(enabled: v),
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
                          onChanged: (v) =>
                              _update((s) => s.resolveDestination = v),
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
                      IosListTile(
                        leadingIcon: CupertinoIcons.list_bullet_indent,
                        leadingIconBg: c.fill,
                        title: 'Правила маршрутизации',
                        subtitle: _s.routingRules.isEmpty
                            ? 'geosite / geoip / домен → proxy·direct·block'
                            : '${_s.routingRules.length} правил',
                        showChevron: true,
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => RoutingRulesScreen(
                              initial: _s.routingRules,
                              onChanged: (rules) =>
                                  _update((s) => s.routingRules = rules),
                            ),
                          ));
                          if (mounted) {
                            setState(() {}); // обновить подпись со счётчиком
                          }
                        },
                      ),
                    ],
                  ),
                ),

                // ── ПОДПИСКИ ─────────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: IosListSection(
                    header: 'Подписки',
                    footer:
                        'Периодически перезагружает серверы из URL-подписок и из маркета в фоне.',
                    children: [
                      IosListTile(
                        leadingIcon: CupertinoIcons.arrow_2_circlepath_circle,
                        leadingIconBg: c.green,
                        title: 'Автообновление',
                        trailing: IosSwitch(
                          value: _s.subAutoUpdate,
                          onChanged: (v) => _update((s) {
                            s.subAutoUpdate = v;
                            // Включили без выбранного интервала — ставим разумный дефолт.
                            if (v && s.subUpdateHours <= 0) {
                              s.subUpdateHours = 12;
                            }
                          }),
                        ),
                      ),
                      if (_s.subAutoUpdate)
                        IosListTile(
                          leadingIcon: CupertinoIcons.clock,
                          leadingIconBg: c.fill,
                          title: 'Интервал',
                          subtitle: _subIntervalLabel(_s.subUpdateHours),
                          showChevron: true,
                          onTap: () => _showOptions(
                            title: 'Интервал обновления',
                            options: kSubUpdateIntervals
                                .where((h) => h > 0)
                                .map(_subIntervalLabel)
                                .toList(),
                            current: _subIntervalLabel(_s.subUpdateHours),
                            onSelect: (v) => _update(
                                (s) => s.subUpdateHours = _subIntervalHours(v)),
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
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
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
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const TlsTricksScreen(),
                        )),
                      ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.shield_lefthalf_fill,
                        leadingIconBg: c.green,
                        title: 'Обход DPI (ByeDPI)',
                        subtitle: 'Десинхронизация, split, fake, TTL',
                        showChevron: true,
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const ByeDpiScreen(),
                        )),
                      ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.lock_circle_fill,
                        leadingIconBg: c.orange,
                        title: 'Авторизация прокси',
                        subtitle: 'Логин/пароль для SOCKS5 и HTTP',
                        showChevron: true,
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const ProxyAuthScreen(),
                        )),
                      ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.map,
                        leadingIconBg: c.fill,
                        title: 'Карта серверов',
                        subtitle: 'Визуализация на карте мира',
                        showChevron: true,
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
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
                        leadingIcon:
                            CupertinoIcons.antenna_radiowaves_left_right,
                        leadingIconBg: c.blue,
                        title: 'Сеть',
                        subtitle: 'Маршрутизация, DNS-перехват, IPv6',
                        showChevron: true,
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
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
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
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
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const StatisticsScreen(),
                        )),
                      ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.doc_text_search,
                        leadingIconBg: c.fill,
                        title: 'VPN-лог',
                        subtitle: 'Журнал работы движка',
                        showChevron: true,
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const LogScreen(),
                        )),
                      ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.wand_stars,
                        leadingIconBg: c.yellow,
                        title: 'Диагностика сети',
                        subtitle: 'Проверить доступность',
                        showChevron: true,
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const DiagnosticsScreen(),
                        )),
                      ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.drop_triangle,
                        leadingIconBg: c.red,
                        title: 'Тест утечки DNS',
                        subtitle: 'Проверить, не утекают ли запросы',
                        showChevron: true,
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const DnsLeakTestScreen(),
                        )),
                      ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.eye,
                        leadingIconBg: c.fill,
                        title: 'Заметность прокси',
                        subtitle: 'WebRTC, JA3, заголовки',
                        showChevron: true,
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
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
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const PrivacyScreen(),
                        )),
                      ),
                      IosListTile(
                        leadingIcon: CupertinoIcons.person_2_fill,
                        leadingIconBg: c.pink,
                        title: 'Авторы',
                        showChevron: true,
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const AuthorPanelScreen(),
                        )),
                      ),
                      if (state.currentUser?.isAdmin == true)
                        IosListTile(
                          leadingIcon: CupertinoIcons.shield_fill,
                          leadingIconBg: c.red,
                          title: 'Модерация',
                          showChevron: true,
                          onTap: () =>
                              Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const AdminPanelScreen(),
                          )),
                        ),
                    ],
                  ),
                ),

                SliverToBoxAdapter(
                  child: SizedBox(
                      height: MediaQuery.of(context).padding.bottom + 32),
                ),
              ],
            ),
            // ── Плавающая кнопка «Назад» (видна при скролле) ──────────────
            Positioned(
              top: 4,
              left: 8,
              child: AnimatedSlide(
                offset: _showBackPill ? Offset.zero : const Offset(-1.4, 0),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: _showBackPill ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: IgnorePointer(
                    ignoring: !_showBackPill,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 9, 14, 9),
                        decoration: BoxDecoration(
                          color: c.bgSecondary,
                          borderRadius:
                              BorderRadius.circular(IosShapes.radiusPill),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(CupertinoIcons.chevron_back,
                              size: 20, color: c.textPrimary),
                          Text(' Назад',
                              style: t.textStyles.subheadline.copyWith(
                                  color: c.textPrimary,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Подписи для пикеров ─────────────────────────────────────────────────
  String _pingModeSubtitle(String mode) => switch (mode) {
        'HTTP' => 'Реальная задержка через туннель',
        'GET' => 'HTTP(S) GET до сервера',
        'UDP' => 'UDP-зонд (best-effort)',
        _ => 'TCP-handshake до сервера',
      };

  String _memoryLimitSubtitle(int mb) {
    if (mb == 0) return 'Без ограничений (для мощных устройств)';
    return '$mb MB';
  }

  String _subIntervalLabel(int hours) {
    if (hours <= 0) return 'Выключено';
    if (hours % 24 == 0) {
      final d = hours ~/ 24;
      return d == 1 ? 'Раз в сутки' : 'Раз в $d сут';
    }
    return 'Каждые $hours ч';
  }

  int _subIntervalHours(String label) {
    for (final h in kSubUpdateIntervals) {
      if (h > 0 && _subIntervalLabel(h) == label) return h;
    }
    return 12;
  }

  // ─── Picker: выбор лимита памяти ─────────────────────────────────────────
  void _showMemoryLimitPicker() {
    const limits = [40, 60, 80, 100, 150, 0]; // 0 = unlimited
    final options = limits.map((mb) {
      if (mb == 0) return 'Без ограничений';
      return '$mb MB';
    }).toList();

    final currentLabel = _s.memoryLimitMB == 0
        ? 'Без ограничений'
        : '${_s.memoryLimitMB} MB';

    _showOptions(
      title: 'Лимит памяти',
      options: options,
      current: currentLabel,
      onSelect: (label) {
        final mb = label == 'Без ограничений'
            ? 0
            : int.parse(label.split(' ').first);
        _update((s) => s.memoryLimitMB = mb);
      },
    );
  }

  // ─── Редактор исключённых маршрутов ──────────────────────────────────────
  void _openExcludedRoutesEditor() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExcludedRoutesScreen(
        initial: _s.excludedRoutes,
        onChanged: (routes) =>
            _update((s) => s.excludedRoutes = List<String>.from(routes)),
      ),
    ));
  }

  // ─── Режим туннеля ───────────────────────────────────────────────────────
  String _tunnelModeSubtitle(String m) => switch (m) {
        'tun_only' => 'Только TUN (без локального прокси)',
        'proxy_only' => 'Только прокси (без VPN, скрыт значок)',
        _ => 'TUN + Proxy (обычный режим)',
      };

  void _showTunnelModePicker() {
    const labels = {
      'tun_proxy': 'TUN + Proxy',
      'tun_only': 'TUN Only',
      'proxy_only': 'Proxy Only',
    };
    _showOptions(
      title: 'Режим туннеля',
      options: labels.values.toList(),
      current: labels[_s.tunnelMode] ?? 'TUN + Proxy',
      onSelect: (label) {
        final mode = labels.entries.firstWhere((e) => e.value == label).key;
        _update((s) {
          s.tunnelMode = mode;
          // proxy_only управляет нативным обходом TUN — синхронизируем.
          s.proxyOnlyMode = mode == 'proxy_only';
        });
      },
    );
  }

  // ─── Тип IP ──────────────────────────────────────────────────────────────
  String _ipTypeSubtitle(String t) => switch (t) {
        'ipv4' => 'Только IPv4',
        'ipv6' => 'Только IPv6',
        _ => 'Авто (IPv4 + IPv6)',
      };

  void _showIpTypePicker() {
    const labels = {'auto': 'Авто', 'ipv4': 'IPv4', 'ipv6': 'IPv6'};
    _showOptions(
      title: 'Тип IP',
      options: labels.values.toList(),
      current: labels[_s.ipType] ?? 'Авто',
      onSelect: (label) {
        final t = labels.entries.firstWhere((e) => e.value == label).key;
        _update((s) => s.ipType = t);
      },
    );
  }

  // ─── Хранение логов ──────────────────────────────────────────────────────
  String _logRetentionSubtitle(String r) => switch (r) {
        '1h' => '1 час',
        '6h' => '6 часов',
        '24h' => '24 часа',
        '7d' => '7 дней',
        _ => 'Хранить всё',
      };

  void _showLogRetentionPicker() {
    const labels = {
      '1h': '1 час',
      '6h': '6 часов',
      '24h': '24 часа',
      '7d': '7 дней',
      'all': 'Хранить всё',
    };
    _showOptions(
      title: 'Хранение логов',
      options: labels.values.toList(),
      current: labels[_s.logRetention] ?? '24 часа',
      onSelect: (label) {
        final r = labels.entries.firstWhere((e) => e.value == label).key;
        _update((s) => s.logRetention = r);
      },
    );
  }

  // ─── Лимиты соединений (idle/TCP/UDP) ────────────────────────────────────
  void _showIntPicker({
    required String title,
    required List<int> options,
    required int current,
    required ValueChanged<int> onSelect,
    String suffix = '',
  }) {
    _showOptions(
      title: title,
      options: options.map((v) => '$v$suffix').toList(),
      current: '$current$suffix',
      onSelect: (label) =>
          onSelect(int.parse(label.replaceAll(suffix, '').trim())),
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
}

// ════════════════════════════════════════════════════════════════════════════
// HEADER
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ios_theme.dart';
import '../main.dart';

class DnsScreen extends StatefulWidget {
  const DnsScreen({super.key});

  @override
  State<DnsScreen> createState() => _DnsScreenState();
}

class _DnsScreenState extends State<DnsScreen> {
  late AppSettings _s;

  @override
  void initState() {
    super.initState();
    final src = AppStateScope.of(context, listen: false).settings;
    _s = AppSettings.copy(src);
  }

  

  void _update(void Function(AppSettings s) mutate) {
    setState(() => mutate(_s));
    AppStateScope.of(context, listen: false).updateSettings(_s);
  }

  static const _domainStrategies = <String>[
    'Авто', 'UseIP', 'UseIPv4', 'UseIPv6', 'PreferIPv4', 'PreferIPv6',
  ];
  static const _onOff = <String>['Не менять', 'Включить', 'Выключить'];
  static const _enhancedModes = <String>['Не менять', 'fake-ip', 'redir-host'];
  static const _fakeIpFilterModes = <String>['Не менять', 'blacklist', 'whitelist'];
  static const _resolveModes = <String>['FakeIP', 'RealIP'];
  static const _ttlPresets = <String>['5 m', '30 m', '1 h', '6 h', '12 h', '24 h'];

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
            SliverToBoxAdapter(child: _ScreenHeader(title: 'DNS')),

            
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Основное',
                children: [
                  IosListTile(
                    leadingIcon: CupertinoIcons.globe,
                    leadingIconBg: c.blue,
                    title: 'Удалённый DNS',
                    subtitle: _s.dnsRemote,
                    showChevron: true,
                    onTap: () => _showTextPicker(
                      title: 'Удалённый DNS',
                      placeholder: 'tcp://8.8.8.8',
                      current: _s.dnsRemote,
                      presets: const [
                        ('tcp://8.8.8.8', 'Google'),
                        ('tcp://1.1.1.1', 'Cloudflare'),
                        ('https://dns.google/dns-query', 'Google DoH'),
                        ('https://cloudflare-dns.com/dns-query', 'Cloudflare DoH'),
                      ],
                      onSelect: (v) => _update((s) => s.dnsRemote = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.arrow_right_arrow_left,
                    leadingIconBg: c.fill,
                    title: 'Стратегия домена удалённого DNS',
                    subtitle: _s.dnsRemoteDomainStrategy,
                    showChevron: true,
                    onTap: () => _showOptions(
                      title: 'Стратегия домена удалённого DNS',
                      options: _domainStrategies,
                      current: _s.dnsRemoteDomainStrategy,
                      onSelect: (v) => _update((s) => s.dnsRemoteDomainStrategy = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.lock_shield,
                    leadingIconBg: c.fill,
                    title: 'Включить поддельный DNS',
                    trailing: IosSwitch(
                      value: _s.dnsFakeDns,
                      onChanged: (v) => _update((s) => s.dnsFakeDns = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.globe,
                    leadingIconBg: c.fill,
                    title: 'Распознаватель исходящего (напрямую)',
                    subtitle: _s.dnsDirect,
                    showChevron: true,
                    onTap: () => _showTextPicker(
                      title: 'Распознаватель исходящего сервера',
                      placeholder: '1.1.1.1',
                      current: _s.dnsDirect,
                      presets: const [
                        ('1.1.1.1', 'Cloudflare'),
                        ('8.8.8.8', 'Google'),
                        ('9.9.9.9', 'Quad9'),
                      ],
                      onSelect: (v) => _update((s) => s.dnsDirect = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.arrow_right_arrow_left,
                    leadingIconBg: c.fill,
                    title: 'Стратегия исходящего домена',
                    subtitle: _s.dnsDirectDomainStrategy,
                    showChevron: true,
                    onTap: () => _showOptions(
                      title: 'Стратегия исходящего домена',
                      options: _domainStrategies,
                      current: _s.dnsDirectDomainStrategy,
                      onSelect: (v) => _update((s) => s.dnsDirectDomainStrategy = v),
                    ),
                  ),
                ],
              ),
            ),

            
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Сервер',
                children: [
                  IosListTile(
                    leadingIcon: CupertinoIcons.bolt,
                    leadingIconBg: c.green,
                    title: 'TUN HijackDNS',
                    subtitle: 'Перехватывать все DNS-запросы TUN',
                    trailing: IosSwitch(
                      value: _s.dnsTunHijackDns,
                      onChanged: (v) => _update((s) => s.dnsTunHijackDns = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.arrow_down_circle,
                    leadingIconBg: c.fill,
                    title: 'Разрешение входящих доменных имён',
                    trailing: IosSwitch(
                      value: _s.dnsAllowIncomingDomains,
                      onChanged: (v) => _update((s) => s.dnsAllowIncomingDomains = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.number,
                    leadingIconBg: c.fill,
                    title: 'Тестовое доменное имя',
                    trailingText: _s.dnsTestDomain,
                    showChevron: true,
                    onTap: () => _showTextPicker(
                      title: 'Тестовое доменное имя',
                      placeholder: 'gstatic.com',
                      current: _s.dnsTestDomain,
                      presets: const [
                        ('gstatic.com', 'Google connectivity check'),
                        ('cloudflare.com', 'Cloudflare'),
                        ('example.com', 'IANA reserved'),
                      ],
                      onSelect: (v) => _update((s) => s.dnsTestDomain = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.timer,
                    leadingIconBg: c.fill,
                    title: 'TTL кэша DNS',
                    trailingText: _s.dnsTtl,
                    showChevron: true,
                    onTap: () => _showOptions(
                      title: 'TTL кэша DNS',
                      options: _ttlPresets,
                      current: _s.dnsTtl,
                      onSelect: (v) => _update((s) => s.dnsTtl = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.list_bullet,
                    leadingIconBg: c.fill,
                    title: 'Включить правила для DNS',
                    trailing: IosSwitch(
                      value: _s.dnsEnableRules,
                      onChanged: (v) => _update((s) => s.dnsEnableRules = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.location_north,
                    leadingIconBg: c.fill,
                    title: '[Прямой поток] Включить ECS',
                    subtitle: 'EDNS Client Subnet - отдавать локальный CDN',
                    trailing: IosSwitch(
                      value: _s.dnsDirectStreamEcs,
                      onChanged: (v) => _update((s) => s.dnsDirectStreamEcs = v),
                    ),
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.arrow_2_circlepath,
                    leadingIconBg: c.fill,
                    title: '[Трафик прокси] Способ разрешения в DNS',
                    trailingText: _s.dnsProxyResolveMode,
                    showChevron: true,
                    onTap: () => _showOptions(
                      title: 'Способ разрешения в DNS',
                      options: _resolveModes,
                      current: _s.dnsProxyResolveMode,
                      onSelect: (v) => _update((s) => s.dnsProxyResolveMode = v),
                    ),
                  ),
                ],
              ),
            ),

            
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Переопределение',
                footer: 'Эти значения подмешиваются в DNS-секцию конфига при '
                    'загрузке профиля. «Не менять» - оставить как в подписке.',
                children: [
                  _overrideRow('Предпочитать HTTP/3', _s.dnsPreferHttp3, _onOff,
                      (v) => _update((s) => s.dnsPreferHttp3 = v)),
                  _overrideRow('Ожидать ответ согласно правилам', _s.dnsRespectRules, _onOff,
                      (v) => _update((s) => s.dnsRespectRules = v)),
                  _overrideRow('Добавить системный DNS', _s.dnsUseSystemDns, _onOff,
                      (v) => _update((s) => s.dnsUseSystemDns = v)),
                  _overrideRow('IPv6', _s.dnsIpv6Override, _onOff,
                      (v) => _update((s) => s.dnsIpv6Override = v)),
                  _overrideRow('Использовать Hosts', _s.dnsUseHosts, _onOff,
                      (v) => _update((s) => s.dnsUseHosts = v)),
                  _overrideRow('Расширенный режим', _s.dnsEnhancedMode, _enhancedModes,
                      (v) => _update((s) => s.dnsEnhancedMode = v)),
                  _overrideText('Сервер имён', _s.dnsNameserver,
                      (v) => _update((s) => s.dnsNameserver = v)),
                  _overrideText('Резервный сервер имён', _s.dnsFallbackNameserver,
                      (v) => _update((s) => s.dnsFallbackNameserver = v)),
                  _overrideText('Сервер имён по умолчанию', _s.dnsDefaultNameserver,
                      (v) => _update((s) => s.dnsDefaultNameserver = v)),
                  _overrideText('Фильтр подставных IP', _s.dnsFakeIpFilter,
                      (v) => _update((s) => s.dnsFakeIpFilter = v)),
                  _overrideRow('Fake-IP Filter Mode', _s.dnsFakeIpFilterMode, _fakeIpFilterModes,
                      (v) => _update((s) => s.dnsFakeIpFilterMode = v)),
                  _overrideText('Резервный GeoIP', _s.dnsFallbackGeoip,
                      (v) => _update((s) => s.dnsFallbackGeoip = v)),
                  _overrideText('Код резервного GeoIP', _s.dnsFallbackGeoipCode,
                      (v) => _update((s) => s.dnsFallbackGeoipCode = v)),
                  _overrideText('Резервный домен', _s.dnsFallbackDomain,
                      (v) => _update((s) => s.dnsFallbackDomain = v)),
                  _overrideText('Резервный IPCIDR', _s.dnsFallbackIpcidr,
                      (v) => _update((s) => s.dnsFallbackIpcidr = v)),
                  _overrideText('Политика сервера имён', _s.dnsNameserverPolicy,
                      (v) => _update((s) => s.dnsNameserverPolicy = v)),
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

  

  Widget _overrideRow(
    String title,
    String current,
    List<String> options,
    ValueChanged<String> onSelect,
  ) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return IosListTile(
      leadingIcon: CupertinoIcons.slider_horizontal_3,
      leadingIconBg: c.fill,
      title: title,
      trailingText: current,
      showChevron: true,
      onTap: () => _showOptions(
        title: title,
        options: options,
        current: current,
        onSelect: onSelect,
      ),
    );
  }

  Widget _overrideText(String title, String current, ValueChanged<String> onSelect) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return IosListTile(
      leadingIcon: CupertinoIcons.pencil,
      leadingIconBg: c.fill,
      title: title,
      trailingText: current,
      showChevron: true,
      onTap: () => _showTextPicker(
        title: title,
        placeholder: 'Не менять',
        current: current,
        presets: const [('Не менять', 'Оставить из подписки')],
        onSelect: onSelect,
      ),
    );
  }

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
      builder: (_) => _OptionsSheet(
        title: title,
        options: options,
        currentValue: current,
        onSelect: onSelect,
      ),
    );
  }

  void _showTextPicker({
    required String title,
    required String placeholder,
    required String current,
    required List<(String, String)> presets,
    required ValueChanged<String> onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TextWithPresetsSheet(
        title: title,
        placeholder: placeholder,
        currentValue: current,
        presets: presets,
        onSelect: onSelect,
      ),
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

class _OptionsSheet extends StatelessWidget {
  final String title;
  final List<String> options;
  final String currentValue;
  final ValueChanged<String> onSelect;

  const _OptionsSheet({
    required this.title,
    required this.options,
    required this.currentValue,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    final tiles = <Widget>[];
    for (int i = 0; i < options.length; i++) {
      final v = options[i];
      final selected = v == currentValue;
      tiles.add(IosListTile(
        title: v,
        trailing: selected
            ? Icon(CupertinoIcons.check_mark, size: 18, color: c.textPrimary)
            : null,
        onTap: () {
          onSelect(v);
          Navigator.of(context).pop();
        },
      ));
      if (i < options.length - 1) {
        tiles.add(Container(margin: const EdgeInsets.only(left: 16), height: 0.5, color: c.separator));
      }
    }

    return Container(
      margin: EdgeInsets.fromLTRB(8, 0, 8, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: c.bgSecondary,
        borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 6),
            width: 36, height: 4,
            decoration: BoxDecoration(color: c.textQuaternary, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(children: [
              Text(title, style: t.textStyles.headline),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Icon(CupertinoIcons.xmark_circle_fill, size: 28, color: c.textQuaternary),
              ),
            ]),
          ),
          ...tiles,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _TextWithPresetsSheet extends StatefulWidget {
  final String title;
  final String placeholder;
  final String currentValue;
  final List<(String, String)> presets;
  final ValueChanged<String> onSelect;

  const _TextWithPresetsSheet({
    required this.title,
    required this.placeholder,
    required this.currentValue,
    required this.presets,
    required this.onSelect,
  });

  @override
  State<_TextWithPresetsSheet> createState() => _TextWithPresetsSheetState();
}

class _TextWithPresetsSheetState extends State<_TextWithPresetsSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentValue);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _apply(String v) {
    final value = v.trim();
    if (value.isEmpty) return;
    widget.onSelect(value);
    Navigator.of(context).pop();
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 6),
              alignment: Alignment.center,
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: c.textQuaternary, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(children: [
                Text(widget.title, style: t.textStyles.headline),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(CupertinoIcons.xmark_circle_fill, size: 28, color: c.textQuaternary),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: IosField(
                controller: _ctrl,
                label: 'Значение',
                placeholder: widget.placeholder,
                keyboardType: TextInputType.text,
                onChanged: (_) {},
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: IosButton(
                label: 'Применить',
                style: IosButtonStyle.primary,
                onPressed: () => _apply(_ctrl.text),
              ),
            ),
            if (widget.presets.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'ПРЕСЕТЫ',
                  style: t.textStyles.footnote.copyWith(color: c.textSecondary, letterSpacing: 0.5),
                ),
              ),
              for (int i = 0; i < widget.presets.length; i++) ...[
                IosListTile(
                  title: widget.presets[i].$1,
                  subtitle: widget.presets[i].$2,
                  trailing: widget.currentValue == widget.presets[i].$1
                      ? Icon(CupertinoIcons.check_mark, size: 18, color: c.textPrimary)
                      : null,
                  onTap: () {
                    _ctrl.text = widget.presets[i].$1;
                    _apply(widget.presets[i].$1);
                  },
                ),
                if (i < widget.presets.length - 1)
                  Container(margin: const EdgeInsets.only(left: 16), height: 0.5, color: c.separator),
              ],
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

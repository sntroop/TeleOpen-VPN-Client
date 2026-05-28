import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ios_theme.dart';
import '../main.dart';

class MetaFeaturesScreen extends StatefulWidget {
  const MetaFeaturesScreen({super.key});

  @override
  State<MetaFeaturesScreen> createState() => _MetaFeaturesScreenState();
}

class _MetaFeaturesScreenState extends State<MetaFeaturesScreen> {
  late AppSettings _s;

  @override
  void initState() {
    super.initState();
    _s = AppSettings.copy(AppStateScope.of(context, listen: false).settings);
  }

  void _update(void Function(AppSettings s) mutate) {
    setState(() => mutate(_s));
    AppStateScope.of(context, listen: false).updateSettings(_s);
  }

  

  

  

  

  

  static const _onOff = <String>['Не менять', 'Включить', 'Выключить'];
  static const _geoModes = <String>['Не менять', 'GeoIP', 'GeoSite', 'GeoIP+GeoSite', 'ASN'];
  static const _findProcessModes = <String>['Не менять', 'always', 'strict', 'off'];
  static const _sniffStrategies = <String>['Не менять', 'normal', 'override-destination', 'force-domain'];

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
            SliverToBoxAdapter(child: _ScreenHeader(title: 'Функции Meta')),

            
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Поведение',
                children: [
                  _optionsRow('Унифицированная задержка', _s.metaUnifiedDelay, _onOff,
                      (v) => _update((s) => s.metaUnifiedDelay = v)),
                  _optionsRow('Режим геоданных', _s.metaGeoMode, _geoModes,
                      (v) => _update((s) => s.metaGeoMode = v)),
                  _optionsRow('Многопоточный TCP', _s.metaMptcp, _onOff,
                      (v) => _update((s) => s.metaMptcp = v)),
                  _optionsRow('Найти режим процесса', _s.metaFindProcess, _findProcessModes,
                      (v) => _update((s) => s.metaFindProcess = v)),
                ],
              ),
            ),

            
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Настройки перехвата доменов',
                footer:
                    'Sniffing анализирует первые пакеты соединения, чтобы извлечь '
                    'имя хоста (SNI/Host header/QUIC), даже если приложение '
                    'обращается напрямую по IP.',
                children: [
                  _optionsRow('Стратегия', _s.metaStrategy, _sniffStrategies,
                      (v) => _update((s) => s.metaStrategy = v)),
                  _textRow('Sniff HTTP Ports', _s.metaSniffHttpPorts, '80,8080-8880',
                      (v) => _update((s) => s.metaSniffHttpPorts = v)),
                  _optionsRow('Sniff HTTP Override Destination', _s.metaSniffHttpOverride, _onOff,
                      (v) => _update((s) => s.metaSniffHttpOverride = v)),
                  _textRow('Sniff TLS Ports', _s.metaSniffTlsPorts, '443,8443',
                      (v) => _update((s) => s.metaSniffTlsPorts = v)),
                  _optionsRow('Sniff TLS Override Destination', _s.metaSniffTlsOverride, _onOff,
                      (v) => _update((s) => s.metaSniffTlsOverride = v)),
                  _textRow('Sniff QUIC Ports', _s.metaSniffQuicPorts, '443',
                      (v) => _update((s) => s.metaSniffQuicPorts = v)),
                  _optionsRow('Sniff QUIC Override Destination', _s.metaSniffQuicOverride, _onOff,
                      (v) => _update((s) => s.metaSniffQuicOverride = v)),
                  _optionsRow('Force DNS Mapping', _s.metaForceDnsMapping, _onOff,
                      (v) => _update((s) => s.metaForceDnsMapping = v)),
                  _optionsRow('Parse Pure IP', _s.metaParsePureIp, _onOff,
                      (v) => _update((s) => s.metaParsePureIp = v)),
                  _optionsRow('Override Destination', _s.metaOverrideDestination, _onOff,
                      (v) => _update((s) => s.metaOverrideDestination = v)),
                  _textRow('Принудительный перехват доменов', _s.metaForceDomain, 'v.douyin.com, +.amemv.com',
                      (v) => _update((s) => s.metaForceDomain = v)),
                  _textRow('Исключения перехвата доменов', _s.metaSkipDomain, '+.push.apple.com',
                      (v) => _update((s) => s.metaSkipDomain = v)),
                  _textRow('Skip Src Address', _s.metaSkipSrc, '192.168.0.0/24',
                      (v) => _update((s) => s.metaSkipSrc = v)),
                  _textRow('Skip Dst Address', _s.metaSkipDst, '10.0.0.0/8',
                      (v) => _update((s) => s.metaSkipDst = v)),
                ],
              ),
            ),

            
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Geo Files',
                footer:
                    'Импорт локальных баз. Поддерживаются форматы .dat/.mmdb. '
                    'После импорта файл сохраняется в каталоге приложения и '
                    'используется ядром при матчинге GEOIP/GEOSITE/ASN-правил.',
                children: [
                  _importRow(
                    title: 'Import GeoIP Database',
                    status: _s.metaGeoipPath,
                    icon: CupertinoIcons.location_solid,
                    bg: c.blue,
                    onTap: () => _runImport('geoip', (name) => _update((s) => s.metaGeoipPath = name)),
                  ),
                  _importRow(
                    title: 'Import GeoSite Database',
                    status: _s.metaGeositePath,
                    icon: CupertinoIcons.globe,
                    bg: c.green,
                    onTap: () => _runImport('geosite', (name) => _update((s) => s.metaGeositePath = name)),
                  ),
                  _importRow(
                    title: 'Import Country Database',
                    status: _s.metaCountryPath,
                    icon: CupertinoIcons.flag,
                    bg: c.orange,
                    onTap: () => _runImport('country', (name) => _update((s) => s.metaCountryPath = name)),
                  ),
                  _importRow(
                    title: 'Import ASN Database',
                    status: _s.metaAsnPath,
                    icon: CupertinoIcons.number_circle,
                    bg: c.purple,
                    onTap: () => _runImport('asn', (name) => _update((s) => s.metaAsnPath = name)),
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

  

  Widget _importRow({
    required String title,
    required String status,
    required IconData icon,
    required Color bg,
    required VoidCallback onTap,
  }) {
    return IosListTile(
      leadingIcon: icon,
      leadingIconBg: bg,
      title: title,
      subtitle: status.isEmpty ? 'Press to import...' : status,
      showChevron: true,
      onTap: onTap,
    );
  }

  
  
  
  
  
  
  
  Future<void> _runImport(String kind, ValueChanged<String> onPicked) async {
    
    
    
    final bridge = AppStateScope.of(context, listen: false).bridge;

    
    final result = await bridge.importGeoFile(kind: kind, sourcePath: '');
    if (!mounted) return;
    if (result == null || result.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Импорт отменён'),
        ),
      );
      return;
    }
    onPicked(result);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Файл импортирован: $result'),
      ),
    );
  }

  Widget _textRow(String title, String current, String placeholder,
      ValueChanged<String> onSelect) {
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
        placeholder: placeholder,
        current: current,
        presets: [('Не менять', 'Оставить из подписки')],
        onSelect: onSelect,
      ),
    );
  }

  Widget _optionsRow(String title, String current, List<String> options,
      ValueChanged<String> onSelect) {
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
        onTap: () { onSelect(v); Navigator.of(context).pop(); },
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

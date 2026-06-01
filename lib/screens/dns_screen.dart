// lib/screens/dns_screen.dart
//
// Расширенный экран настроек DNS. Объединяет:
//   - "Удалённый/исходящий DNS" (как было)
//   - Настройки сервера DNS (TUN HijackDNS, входящие домены, статический IP, TTL,
//     тестовый домен, правила DNS, ECS, способ разрешения в DNS)
//   - Переопределение DNS (HTTP/3, ожидание, hosts, IPv6, расширенный режим,
//     основной/резервный/по умолчанию nameservers, фильтр подставных IP,
//     Fake-IP Filter Mode, fallback GeoIP/IPCIDR/domain, политика).
//
// Все переключатели сохраняют состояние локально (этот экран — UI-слой).
// Привязку к реальному ядру (clash/mihomo bridge) делает vpn_bridge.dart —
// см. метки TODO(bridge) ниже.

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

  // (используем AppSettings.copy из main.dart)

  void _update(void Function(AppSettings s) mutate) {
    setState(() => mutate(_s));
    AppStateScope.of(context, listen: false).updateSettings(_s);
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
            const SliverToBoxAdapter(child: _ScreenHeader(title: 'DNS')),

            // ─── Базовый блок (удалённый/исходящий) ──────────────────────
            // Оставлены только поля, которые реально применяются ядром xray
            // (HysteriaTunVpnService.ensureTunInbound читает dns_remote/
            // dns_direct/dns_fake). Остальные mihomo/meta-опции (стратегии
            // доменов, TTL, ECS, fake-ip фильтры, override-блок) xray не
            // поддерживает — скрыты, чтобы не вводить в заблуждение.
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

  // ── helpers ────────────────────────────────────────────────────────────

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

// ─── Header ─────────────────────────────────────────────────────────────────

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

// ─── Sheets ─────────────────────────────────────────────────────────────────

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

// lib/screens/privacy_screen.dart
//
// «Безопасность и конфиденциальность» — экран доверия.
//   - SHA-256 сертификата подписи установленного APK + сверка с прод-ключом
//     (TeleOpen ставится сайдлоадом; юзер может убедиться, что сборка не подменена).
//   - Честный список «что приложение хранит» (JWT в Keystore, нет логов трафика).
//
// Cert читается нативкой (MainActivity.getSigningCertSha256), сверка — logic/trust.dart.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ios_theme.dart';
import '../logic/trust.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  String? _certSha; // нормализованный фактический хэш, null = ещё/не удалось
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCert();
  }

  Future<void> _loadCert() async {
    final sha = await TrustInfo.fetchCertSha256();
    if (!mounted) return;
    setState(() {
      _certSha = sha;
      _loading = false;
    });
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label скопировано'), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    final actual = _certSha;
    final matches = actual != null && TrustInfo.matches(actual);

    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(
              child: _ScreenHeader(title: 'Безопасность'),
            ),

            // ─── Подпись приложения ──────────────────────────────────────
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Подпись приложения',
                footer:
                    'TeleOpen устанавливается мимо магазинов. Сверьте отпечаток '
                    'с опубликованным, чтобы убедиться, что сборка подлинная. '
                    'Debug-сборки подписаны другим ключом — для них отпечаток не совпадёт.',
                children: [
                  IosListTile(
                    leadingIcon: matches
                        ? CupertinoIcons.checkmark_seal_fill
                        : (_loading
                            ? CupertinoIcons.hourglass
                            : CupertinoIcons.exclamationmark_triangle_fill),
                    leadingIconBg: _loading
                        ? c.fill
                        : (matches ? c.green : c.orange),
                    title: _loading
                        ? 'Проверяю подпись…'
                        : (matches
                            ? 'Подпись подлинная'
                            : (actual == null
                                ? 'Не удалось прочитать подпись'
                                : 'Подпись не совпадает')),
                    subtitle: _loading
                        ? null
                        : (matches
                            ? 'Совпадает с прод-ключом'
                            : (actual == null
                                ? 'Нативный модуль недоступен'
                                : 'Это не официальная release-сборка')),
                  ),
                  if (actual != null)
                    IosListTile(
                      leadingIcon: CupertinoIcons.doc_on_clipboard,
                      leadingIconBg: c.fill,
                      title: 'Отпечаток SHA-256',
                      subtitle: actual,
                      onTap: () => _copy(actual, 'Отпечаток'),
                    ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.checkmark_shield,
                    leadingIconBg: c.fill,
                    title: 'Ожидаемый (release)',
                    subtitle: TrustInfo.expectedReleaseCertSha256,
                    onTap: () => _copy(
                        TrustInfo.expectedReleaseCertSha256, 'Эталонный отпечаток'),
                  ),
                ],
              ),
            ),

            // ─── Что мы храним ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: IosListSection(
                header: 'Что приложение хранит',
                footer:
                    'Данные остаются на устройстве. Трафик не логируется приложением.',
                children: [
                  IosListTile(
                    leadingIcon: CupertinoIcons.lock_fill,
                    leadingIconBg: c.green,
                    title: 'Токен авторизации (JWT)',
                    subtitle: 'В системном Keystore/Keychain, в зашифрованном виде',
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.device_phone_portrait,
                    leadingIconBg: c.fill,
                    title: 'Серверы и настройки',
                    subtitle: 'Локально на устройстве (SharedPreferences)',
                  ),
                  IosListTile(
                    leadingIcon: CupertinoIcons.eye_slash_fill,
                    leadingIconBg: c.fill,
                    title: 'Логи трафика',
                    subtitle: 'Не ведутся. Логи диагностики — только локально, по запросу',
                  ),
                ],
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
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

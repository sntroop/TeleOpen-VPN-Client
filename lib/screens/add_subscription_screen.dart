// lib/screens/add_subscription_screen.dart
//
// Экран добавления подписки.
// Три способа: из буфера обмена, по QR-коду, вручную + вкладка «Подписка».

library add_subscription_screen;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../ios_theme.dart';
import '../main.dart';
import '../models/mtproto_proxy.dart';
import '../logic/market_api.dart';
import '../logic/subscriptions.dart';

// ── режимы экрана ─────────────────────────────────────────────────────────────
part 'add_subscription/parts.dart';

enum _AddMode { none, clipboard, qr, manual, subscription, teleopen }

class AddSubscriptionScreen extends StatefulWidget {
  const AddSubscriptionScreen({super.key});

  @override
  State<AddSubscriptionScreen> createState() => _AddSubscriptionScreenState();
}

class _AddSubscriptionScreenState extends State<AddSubscriptionScreen> {
  final _urlCtrl        = TextEditingController();
  final _titleCtrl      = TextEditingController();
  final _manualCtrl     = TextEditingController();
  final _teleopenCtrl   = TextEditingController();

  _AddMode _mode = _AddMode.none;

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _titleCtrl.dispose();
    _manualCtrl.dispose();
    _teleopenCtrl.dispose();
    super.dispose();
  }

  // ── clipboard ──────────────────────────────────────────────────────────────
  Future<void> _addFromClipboard() async {
    // Берём state синхронно, до любого await — позже context может стать
    // невалидным (use_build_context_synchronously).
    final state = AppStateScope.of(context);
    setState(() { _loading = true; _error = null; });

    String raw = '';
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      raw = data?.text?.trim() ?? '';
    } catch (_) {
      // Чтение буфера не удалось — raw останется пустым, и ниже пользователь
      // увидит понятную ошибку «Буфер обмена пуст». Отдельный лог не нужен.
    }

    if (raw.isEmpty) {
      setState(() { _loading = false; _error = 'Буфер обмена пуст'; });
      return;
    }

    // Если в буфере одна HTTP/HTTPS-ссылка (raw.githubusercontent.com и т.п.)
    // — качаем как подписку.
    if (_looksLikeHttpUrl(raw)) {
      final err = await state.addSubscription(url: raw);
      if (!mounted) return;
      if (err != null) {
        setState(() { _loading = false; _error = err; });
      } else {
        Navigator.of(context).pop();
      }
      return;
    }

    final lines = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final supported = lines.where((l) {
      final lo = l.toLowerCase();
      return lo.startsWith('vless://') ||
             lo.startsWith('vmess://') ||
             lo.startsWith('trojan://') ||
             lo.startsWith('ssr://') ||
             lo.startsWith('ss://') ||
             lo.startsWith('hysteria://') ||
             lo.startsWith('hysteria2://') ||
             lo.startsWith('hy2://') ||
             lo.startsWith('tuic://') ||
             lo.startsWith('socks://');
    }).toList();

    if (supported.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'В буфере нет поддерживаемых URI (vless/vmess/trojan/…) или ссылки на подписку';
      });
      return;
    }

    int added = 0;
    String? lastErr;
    for (final uri in supported) {
      final err = state.addManualNode(uri);
      if (err == null) {
        added++;
      } else {
        lastErr = err;
      }
    }

    if (!mounted) return;
    if (added == 0) {
      setState(() { _loading = false; _error = lastErr ?? 'Не удалось добавить серверы'; });
    } else {
      Navigator.of(context).pop();
    }
  }

  // ── TeleOpen код (VPN или MTProto) ────────────────────────────────────────
  Future<void> _addTeleopenCode() async {
    final input = _teleopenCtrl.text.trim();
    if (input.isEmpty) {
      setState(() => _error = 'Введите код или ссылку');
      return;
    }
    setState(() { _loading = true; _error = null; });

    // Извлекаем чистый 6-значный код
    String extractCode(String s) {
      final trimmed = s.trim().toUpperCase();
      if (RegExp(r'^[A-Z0-9]{6}$').hasMatch(trimmed)) return trimmed;
      final uri = Uri.tryParse(s.trim());
      if (uri != null && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.last.toUpperCase();
      }
      if (trimmed.length >= 6) return trimmed.substring(trimmed.length - 6);
      return trimmed;
    }

    final code = extractCode(input);

    // 1) Пробуем как MTProto-код: GET /v1/mtproto/<code>
    try {
      final mtUrl = input.contains('/v1/mtproto/')
          ? (input.startsWith('http') ? input : 'https://$input')
          : '$kApiBase/v1/mtproto/$code';
      final resp = await http.get(Uri.parse(mtUrl))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        if (body.containsKey('proxies')) {
          final title = (body['title'] as String?) ?? 'MTProto $code';
          final rawList = body['proxies'] as List;
          final proxies = rawList
              .whereType<Map<String, dynamic>>()
              .map((p) => MtProtoProxy.tryParse(
                    p['link'] as String? ?? '',
                    name: p['displayName'] as String? ?? '',
                  ))
              .whereType<MtProtoProxy>()
              .toList();
          if (proxies.isNotEmpty && mounted) {
            final group = MtProtoProxyGroup(
              id: 'code_$code',
              title: title,
              proxies: proxies,
            );
            AppStateScope.of(context, listen: false).addMtProtoGroup(group);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('«$title» добавлена — ${proxies.length} прокси'),
              duration: const Duration(seconds: 2),
            ));
            Navigator.of(context).pop();
            return;
          }
        }
      }
    } catch (_) {}

    // 2) Пробуем как VPN-подписку: /sub/<code>
    try {
      final url = input.contains('://') || input.contains(kApiBase.split('://').last)
          ? (input.startsWith('http') ? input : 'https://$input')
          : '$kApiBase/sub/$code';
      final result = await SubscriptionLoader.load(url);
      if (!mounted) return;
      if (result.error == null && result.nodes.isNotEmpty) {
        final title = result.groupTitle.isNotEmpty ? result.groupTitle : 'Код $code';
        final err = await AppStateScope.of(context, listen: false)
            .addSubscription(url: url, title: title);
        if (!mounted) return;
        if (err != null) throw Exception(err);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('«$title» добавлена — ${result.nodes.length} серверов'),
          duration: const Duration(seconds: 2),
        ));
        Navigator.of(context).pop();
        return;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
      return;
    }

    if (mounted) {
      setState(() {
        _error = 'Код не найден или истёк. Попробуйте ещё раз.';
        _loading = false;
      });
    }
  }

  bool _looksLikeHttpUrl(String s) {
    final t = s.trim();
    if (t.contains('\n')) return false;
    final lo = t.toLowerCase();
    // t.me/proxy и t.me/socks — MTProto/SOCKS deep-link, не подписка
    if (lo.contains('t.me/proxy') || lo.contains('t.me/socks')) return false;
    return lo.startsWith('http://') || lo.startsWith('https://');
  }

  // ── QR ────────────────────────────────────────────────────────────────────
  Future<void> _scanQr() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScannerPage()),
    );
    if (result == null || !mounted) return;
    setState(() { _loading = true; _error = null; });
    final err = AppStateScope.of(context).addManualNode(result.trim());
    if (!mounted) return;
    if (err != null) {
      setState(() { _loading = false; _error = err; });
    } else {
      Navigator.of(context).pop();
    }
  }

  // ── manual URI ────────────────────────────────────────────────────────────
  Future<void> _addManual() async {
    final raw = _manualCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Вставьте или введите URI сервера');
      return;
    }
    setState(() { _loading = true; _error = null; });

    // Если введена HTTP/HTTPS-ссылка — скачиваем как подписку
    if (_looksLikeHttpUrl(raw)) {
      final state = AppStateScope.of(context);
      final err = await state.addSubscription(url: raw);
      if (!mounted) return;
      if (err != null) {
        setState(() { _loading = false; _error = err; });
      } else {
        Navigator.of(context).pop();
      }
      return;
    }

    final lines = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final state = AppStateScope.of(context);
    int added = 0;
    String? lastErr;
    for (final uri in lines) {
      final err = state.addManualNode(uri);
      if (err == null) {
        added++;
      } else {
        lastErr = err;
      }
    }

    if (!mounted) return;
    if (added == 0) {
      setState(() { _loading = false; _error = lastErr ?? 'Не удалось распарсить URI'; });
    } else {
      Navigator.of(context).pop();
    }
  }

  // ── subscription URL ───────────────────────────────────────────────────────
  Future<void> _addSubscription() async {
    final url = _urlCtrl.text.trim();
    final title = _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Введите URL подписки');
      return;
    }
    setState(() { _loading = true; _error = null; });

    final state = AppStateScope.of(context);
    final err = await state.addSubscription(url: url, title: title);
    if (!mounted) return;
    if (err != null) {
      setState(() { _loading = false; _error = err; });
    } else {
      Navigator.of(context).pop();
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────
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
                      Text(' Назад', style: t.textStyles.body.copyWith(color: c.textPrimary)),
                    ]),
                  ),
                ),
                const Spacer(),
              ]),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Row(children: [
                Text('Добавить', style: t.textStyles.largeTitle),
              ]),
            ),

            // Main content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── три кнопки ─────────────────────────────────────────
                    _MethodButton(
                      icon: CupertinoIcons.doc_on_clipboard,
                      label: 'Добавить из буфера обмена',
                      subtitle: 'Vless/vmess/trojan-ссылки или URL подписки (GitHub raw)',
                      selected: _mode == _AddMode.clipboard,
                      loading: _loading && _mode == _AddMode.clipboard,
                      onTap: () {
                        setState(() { _mode = _AddMode.clipboard; _error = null; });
                        _addFromClipboard();
                      },
                      t: t,
                      c: c,
                    ),
                    const SizedBox(height: 10),
                    _MethodButton(
                      icon: CupertinoIcons.qrcode_viewfinder,
                      label: 'Добавить по QR',
                      subtitle: 'Сканировать QR-код сервера',
                      selected: _mode == _AddMode.qr,
                      loading: _loading && _mode == _AddMode.qr,
                      onTap: () {
                        setState(() { _mode = _AddMode.qr; _error = null; });
                        _scanQr();
                      },
                      t: t,
                      c: c,
                    ),
                    const SizedBox(height: 10),
                    _MethodButton(
                      icon: CupertinoIcons.pencil,
                      label: 'Ввести вручную',
                      subtitle: 'URI сервера или несколько строк',
                      selected: _mode == _AddMode.manual,
                      loading: false,
                      onTap: () => setState(() {
                        _mode = _mode == _AddMode.manual ? _AddMode.none : _AddMode.manual;
                        _error = null;
                      }),
                      t: t,
                      c: c,
                    ),

                    // ── разворачивающаяся форма — вручную ──────────────────
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      child: _mode == _AddMode.manual
                          ? Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: _manualForm(t, c),
                            )
                          : const SizedBox.shrink(),
                    ),

                    const SizedBox(height: 20),

                    // ── разделитель ────────────────────────────────────────
                    Row(children: [
                      Expanded(child: Divider(color: c.separator, thickness: 0.5)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'или по URL подписки',
                          style: t.textStyles.footnote.copyWith(color: c.textSecondary),
                        ),
                      ),
                      Expanded(child: Divider(color: c.separator, thickness: 0.5)),
                    ]),

                    const SizedBox(height: 16),

                    // ── кнопка подписки ────────────────────────────────────
                    _MethodButton(
                      icon: CupertinoIcons.link,
                      label: 'Добавить подписку',
                      subtitle: 'v2rayN, Hiddify, plaintext URL',
                      selected: _mode == _AddMode.subscription,
                      loading: _loading && _mode == _AddMode.subscription,
                      onTap: () => setState(() {
                        _mode = _mode == _AddMode.subscription
                            ? _AddMode.none
                            : _AddMode.subscription;
                        _error = null;
                      }),
                      t: t,
                      c: c,
                    ),

                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      child: _mode == _AddMode.subscription
                          ? Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: _subForm(t, c),
                            )
                          : const SizedBox.shrink(),
                    ),

                    const SizedBox(height: 10),

                    // ── кнопка TeleOpen-кода ───────────────────────────────
                    _MethodButton(
                      icon: CupertinoIcons.number,
                      label: 'Ввести код TeleOpen',
                      subtitle: '6-значный код или ссылка — VPN и MTProto',
                      selected: _mode == _AddMode.teleopen,
                      loading: _loading && _mode == _AddMode.teleopen,
                      onTap: () => setState(() {
                        _mode = _mode == _AddMode.teleopen
                            ? _AddMode.none
                            : _AddMode.teleopen;
                        _error = null;
                      }),
                      t: t,
                      c: c,
                    ),

                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      child: _mode == _AddMode.teleopen
                          ? Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: _teleopenForm(t, c),
                            )
                          : const SizedBox.shrink(),
                    ),

                    // ── ошибка ─────────────────────────────────────────────
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      _ErrorBanner(error: _error!, t: t, c: c),
                    ],
                  ],
                ),
              ),
            ),

            // Bottom action button (только для форм ввода)
            if (_mode == _AddMode.manual || _mode == _AddMode.subscription || _mode == _AddMode.teleopen)
              Padding(
                padding: EdgeInsets.fromLTRB(
                    16, 8, 16, MediaQuery.of(context).padding.bottom + 12),
                child: IosButton(
                  label: switch (_mode) {
                    _AddMode.subscription => 'Добавить подписку',
                    _AddMode.teleopen     => 'Добавить по коду',
                    _                    => 'Добавить сервер',
                  },
                  style: IosButtonStyle.primary,
                  loading: _loading,
                  onPressed: _loading
                      ? null
                      : switch (_mode) {
                          _AddMode.subscription => _addSubscription,
                          _AddMode.teleopen     => _addTeleopenCode,
                          _                    => _addManual,
                        },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── sub-forms ──────────────────────────────────────────────────────────────
  Widget _manualForm(IosThemeData t, IosColors c) {
    return IosCard(
      radius: IosShapes.radiusLarge,
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IosField(
          controller: _manualCtrl,
          label: 'URI сервера или ссылка',
          placeholder: 'vless://…  vmess://…  trojan://…\nили https://raw.githubusercontent.com/…',
          maxLines: 5,
        ),
        const SizedBox(height: 10),
        Text(
          'Поддерживаются: VLESS, VMess, Trojan, Hysteria2, Shadowsocks, SOCKS,\nа также HTTP(S)-ссылки на список конфигов (GitHub raw и подобные).',
          style: t.textStyles.footnote.copyWith(color: c.textSecondary),
        ),
      ]),
    );
  }

  Widget _subForm(IosThemeData t, IosColors c) {
    return IosCard(
      radius: IosShapes.radiusLarge,
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IosField(
          controller: _urlCtrl,
          label: 'URL подписки',
          placeholder: 'https://example.com/sub',
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),
        IosField(
          controller: _titleCtrl,
          label: 'Название (опционально)',
          placeholder: 'Моя подписка',
        ),
        const SizedBox(height: 10),
        Text(
          'Поддерживаются ссылки на подписки в форматах v2rayN (base64), Hiddify, plaintext.',
          style: t.textStyles.footnote.copyWith(color: c.textSecondary),
        ),
      ]),
    );
  }
  Widget _teleopenForm(IosThemeData t, IosColors c) {
    return IosCard(
      radius: IosShapes.radiusLarge,
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IosField(
          controller: _teleopenCtrl,
          label: 'Код или ссылка',
          placeholder: 'ABC123  или  https://teleopen.space/v1/mtproto/ABC123',
          keyboardType: TextInputType.text,
        ),
        const SizedBox(height: 10),
        Text(
          'Работает для VPN-серверов и MTProto-прокси. Просто вставь код или ссылку — тип определится автоматически.',
          style: t.textStyles.footnote.copyWith(color: c.textSecondary),
        ),
      ]),
    );
  }
}

// ── Кнопка-метод ─────────────────────────────────────────────────────────────

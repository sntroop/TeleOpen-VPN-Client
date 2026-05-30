// lib/screens/share/join_tab.dart
// Вкладка JOIN: ввод кода/ссылки → импорт MTProto-группы или VPN-подписки.
// part of share_screen.

part of '../share_screen.dart';

// ══════════════════════════════════════════════════════════════════════════
// TAB 2: Ввести код
// ══════════════════════════════════════════════════════════════════════════

class _JoinTab extends StatefulWidget {
  const _JoinTab();

  @override
  State<_JoinTab> createState() => _JoinTabState();
}

class _JoinTabState extends State<_JoinTab> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Из строки вида "ABC123", "https://teleopen.space/sub/ABC123"
  /// или "teleopen.space/sub/ABC123" извлекаем чистый код.
  String _extractCode(String input) {
    final trimmed = input.trim().toUpperCase();
    // Если уже 6-значный код
    if (RegExp(r'^[A-Z0-9]{6}$').hasMatch(trimmed)) return trimmed;
    // Если ссылка — берём последний сегмент
    final uri = Uri.tryParse(input.trim());
    if (uri != null && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last.toUpperCase();
    }
    // Fallback: последние 6 символов
    if (trimmed.length >= 6) return trimmed.substring(trimmed.length - 6);
    return trimmed;
  }

  Future<void> _join() async {
    final input = _ctrl.text.trim();
    if (input.isEmpty) { setState(() => _error = 'Введите код или ссылку'); return; }

    setState(() { _loading = true; _error = null; });

    try {
      final code = _extractCode(input);

      // 1) Пробуем как MTProto-код/ссылку: GET /v1/mtproto/<code>
      //    Если ответ содержит поле "proxies" — это MTProto-группа.
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
                .map((p) {
                  final link = p['link'] as String? ?? '';
                  final name = p['displayName'] as String? ?? '';
                  return MtProtoProxy.tryParse(link, name: name);
                })
                .whereType<MtProtoProxy>()
                .toList();
            if (proxies.isNotEmpty && mounted) {
              final group = MtProtoProxyGroup(
                id: 'code_$code',
                title: title,
                proxies: proxies,
              );
              AppStateScope.of(context, listen: false).addMtProtoGroup(group);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('«$title» добавлена — ${proxies.length} прокси'),
                duration: const Duration(seconds: 2),
              ));
              Navigator.of(context).pop();
              return;
            }
          }
        }
      } catch (_) {
        // не MTProto — идём дальше к VPN
      }

      // 2) Пробуем как VPN-подписку (/sub/<code>)
      final url = input.contains('://') || input.contains(kApiBase.split('://').last)
        ? (input.startsWith('http') ? input : 'https://$input')
        : '$kApiBase/sub/$code';

      final result = await SubscriptionLoader.load(url);
      if (!mounted) return;

      if (result.error != null) throw Exception(result.error);
      if (result.nodes.isEmpty) throw Exception('Серверы не найдены');

      final state = AppStateScope.of(context, listen: false);
      final title = result.groupTitle.isNotEmpty
        ? result.groupTitle
        : 'Код $code';

      final err = await state.addSubscription(url: url, title: title);
      if (!mounted) return;
      if (err != null) throw Exception(err);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('«$title» добавлена — ${result.nodes.length} серверов'),
        duration: const Duration(seconds: 2),
      ));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      physics: const BouncingScrollPhysics(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        IosCard(
          padding: const EdgeInsets.all(12),
          child: IosField(
            controller: _ctrl,
            label: 'Код или ссылка',
            placeholder: 'ABC123  или  https://...',
            keyboardType: TextInputType.text,
          ),
        ),

        const SizedBox(height: 16),

        if (_error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.red.withValues(alpha: 0.12),
              borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
            ),
            child: Row(children: [
              Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 18, color: c.red),
              const SizedBox(width: 8),
              Expanded(child: Text(_error!, style: t.textStyles.subheadline.copyWith(color: c.red))),
            ]),
          ),

        IosButton(
          label: 'Добавить серверы',
          style: IosButtonStyle.primary,
          leadingIcon: CupertinoIcons.arrow_down_circle_fill,
          loading: _loading,
          onPressed: _loading ? null : _join,
        ),

        const SizedBox(height: 12),
        Text(
          'Введи 6-значный код или вставь ссылку от друга — серверы появятся в твоих подписках.',
          style: t.textStyles.footnote.copyWith(color: c.textTertiary),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }
}

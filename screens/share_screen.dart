import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../ios_theme.dart';
import '../main.dart';
import '../models/vpn_node.dart';
import '../models/mtproto_proxy.dart';
import '../logic/market_api.dart';
import '../logic/subscriptions.dart';
import '../widgets/telegram_proxy_sheet.dart';

class ShareScreen extends StatefulWidget {
  
  final VpnGroup? group;

  
  
  final MtProtoProxyGroup? initialMtProtoGroup;

  const ShareScreen({super.key, this.group, this.initialMtProtoGroup});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  int _tab = 0; 

  @override
  void initState() {
    super.initState();
    if (widget.group != null) _tab = 0;
    if (widget.initialMtProtoGroup != null) _tab = 2;
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          
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
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(children: [
              Text('Поделиться', style: t.textStyles.largeTitle),
            ]),
          ),

          
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: IosSegment(
              activeIndex: _tab,
              onChanged: (i) => setState(() => _tab = i),
              items: const [
                IosSegmentItem('Создать код'),
                IosSegmentItem('Ввести код'),
                IosSegmentItem('MTProto'),
              ],
            ),
          ),

          Expanded(
            child: switch (_tab) {
              0 => _CreateTab(initialGroup: widget.group),
              1 => const _JoinTab(),
              _ => _MtProtoTab(initialGroup: widget.initialMtProtoGroup),
            },
          ),
        ]),
      ),
    );
  }
}

class _CreateTab extends StatefulWidget {
  final VpnGroup? initialGroup;
  const _CreateTab({this.initialGroup});

  @override
  State<_CreateTab> createState() => _CreateTabState();
}

class _CreateTabState extends State<_CreateTab> {
  
  Map<String, Set<String>> _selected = {};
  Map<String, String> _customNames = {}; 
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _trafficCtrl = TextEditingController(); 
  DateTime? _expireDate;
  bool _loading = false;
  String? _code;
  String? _link;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialGroup != null) {
      final g = widget.initialGroup!;
      _titleCtrl.text = g.title;
      _selected[g.id] = g.nodes.map((n) => n.id).toSet();
    }
  }

  
  List<VpnNode> _allSelectedNodes(AppState state) {
    final result = <VpnNode>[];
    for (final g in state.groups) {
      final ids = _selected[g.id];
      if (ids == null || ids.isEmpty) continue;
      for (final n in g.nodes) {
        if (ids.contains(n.id)) result.add(n);
      }
    }
    return result;
  }

  int get _totalSelected =>
      _selected.values.fold<int>(0, (sum, ids) => sum + ids.length);

  void _toggleNode(String groupId, String nodeId) {
    setState(() {
      final ids = _selected.putIfAbsent(groupId, () => {});
      if (ids.contains(nodeId)) {
        ids.remove(nodeId);
      } else {
        ids.add(nodeId);
      }
    });
  }

  void _toggleGroup(VpnGroup g) {
    setState(() {
      final ids = _selected.putIfAbsent(g.id, () => {});
      if (ids.length == g.nodes.length) {
        ids.clear();
      } else {
        ids.addAll(g.nodes.map((n) => n.id));
      }
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _trafficCtrl.dispose();
    super.dispose();
  }

  void _showRenameNodeDialog(BuildContext context, VpnNode node) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final ctrl = TextEditingController(text: _customNames[node.id] ?? node.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Переименовать', style: t.textStyles.headline),
        content: IosField(
          controller: ctrl,
          label: 'Новое название',
          placeholder: node.name,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Отмена', style: t.textStyles.body.copyWith(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final val = ctrl.text.trim();
              setState(() {
                if (val.isEmpty || val == node.name) {
                  _customNames.remove(node.id);
                } else {
                  _customNames[node.id] = val;
                }
              });
              Navigator.of(ctx).pop();
            },
            child: Text('Сохранить', style: t.textStyles.body.copyWith(color: c.textPrimary)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickExpireDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expireDate ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() => _expireDate = picked);
    }
  }

  Future<void> _create() async {
    final state = AppStateScope.of(context, listen: false);
    final selected = _allSelectedNodes(state);

    if (selected.isEmpty) {
      setState(() => _error = 'Выберите хотя бы один сервер');
      return;
    }

    final title = _titleCtrl.text.trim().isEmpty ? 'Мои серверы' : _titleCtrl.text.trim();
    final description = _descCtrl.text.trim();

    
    int? trafficTotal;
    final gbText = _trafficCtrl.text.trim();
    if (gbText.isNotEmpty) {
      final gb = double.tryParse(gbText);
      if (gb != null && gb > 0) {
        trafficTotal = (gb * 1024 * 1024 * 1024).toInt();
      }
    }

    
    int? trafficExpire;
    if (_expireDate != null) {
      trafficExpire = _expireDate!.millisecondsSinceEpoch ~/ 1000;
    }

    setState(() { _loading = true; _error = null; _code = null; _link = null; });
    try {
      final nodes = selected.map((n) => {
        'uri': n.rawUri,
        'displayName': _customNames[n.id] ?? n.name,
      }).toList();

      final body = <String, dynamic>{
        'title': title,
        'nodes': nodes,
      };
      if (description.isNotEmpty) body['description'] = description;
      if (trafficTotal != null) body['traffic_total'] = trafficTotal;
      if (trafficExpire != null) body['traffic_expire'] = trafficExpire;

      final resp = await http.post(
        Uri.parse('$kApiBase/v1/config/create'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      final code = (jsonDecode(resp.body) as Map)['code'] as String;

      setState(() {
        _code = code;
        _link = '$kApiBase/sub/$code';
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Скопировано'),
      duration: Duration(seconds: 1),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final state = AppStateScope.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      physics: const BouncingScrollPhysics(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        
        if (_code != null) ...[
          _CodeCard(code: _code!, link: _link!, onCopyCode: () => _copy(_code!), onCopyLink: () => _copy(_link!)),
          const SizedBox(height: 12),
          Text(
            'Эту ссылку можно вставить в Hiddify, v2rayNG, Streisand и другие клиенты.',
            style: t.textStyles.footnote.copyWith(color: c.textTertiary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          IosButton(
            label: 'Создать ещё одну',
            style: IosButtonStyle.secondary,
            leadingIcon: CupertinoIcons.refresh,
            onPressed: () => setState(() { _code = null; _link = null; }),
          ),
        ] else ...[

          
          if (state.groups.isEmpty)
            IosListSection(
              header: 'Серверы',
              children: [IosListTile(title: 'Нет добавленных серверов')],
            )
          else
            ...state.groups.map((g) {
              final groupIds = _selected[g.id] ?? {};
              final allSelected = groupIds.length == g.nodes.length && g.nodes.isNotEmpty;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  IosListSection(
                    header: '${g.title} (${groupIds.length} из ${g.nodes.length})',
                    children: [
                      
                      IosListTile(
                        title: allSelected ? 'Снять выделение' : 'Выбрать все',
                        leadingIcon: allSelected
                            ? CupertinoIcons.checkmark_square
                            : CupertinoIcons.square,
                        leadingIconBg: c.fill,
                        onTap: () => _toggleGroup(g),
                      ),
                      
                      ...g.nodes.map((n) {
                        final sel = groupIds.contains(n.id);
                        final displayName = _customNames[n.id] ?? n.name;
                        final isRenamed = _customNames.containsKey(n.id);
                        return Container(
                          constraints: const BoxConstraints(minHeight: 52),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(children: [
                            
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _showRenameNodeDialog(context, n),
                              child: Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: c.fill,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(CupertinoIcons.pencil, size: 17, color: c.textPrimary),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _toggleNode(g.id, n.id),
                                child: Row(children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(displayName, style: t.textStyles.body.copyWith(color: c.textPrimary)),
                                        Text(
                                          isRenamed
                                              ? '✏️ ${n.name} · ${n.protocolLabel} · ${n.address}'
                                              : '${n.protocolLabel} · ${n.address}',
                                          style: t.textStyles.footnote.copyWith(color: c.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 22, height: 22,
                                    decoration: BoxDecoration(
                                      color: sel ? c.textPrimary : Colors.transparent,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: sel ? c.textPrimary : c.textTertiary, width: 1.5),
                                    ),
                                    child: sel ? Icon(CupertinoIcons.check_mark, size: 13, color: c.bgSecondary) : null,
                                  ),
                                ]),
                              ),
                            ),
                          ]),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              );
            }),

          
          IosListSection(
            header: 'Информация',
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: IosField(
                  controller: _titleCtrl,
                  label: 'Название подписки',
                  placeholder: 'Например: Мои серверы',
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: IosField(
                  controller: _descCtrl,
                  label: 'Описание (необязательно)',
                  placeholder: 'Для друзей, серверы в Европе...',
                  maxLines: 3,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          
          IosListSection(
            header: 'Лимиты (необязательно)',
            footer: 'Лимиты отображаются в VPN-клиентах, поддерживающих subscription-userinfo.',
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: IosField(
                  controller: _trafficCtrl,
                  label: 'Лимит трафика (ГБ)',
                  placeholder: 'Например: 100',
                  keyboardType: TextInputType.number,
                ),
              ),
              IosListTile(
                title: _expireDate != null
                    ? 'Истекает: ${_expireDate!.day}.${_expireDate!.month.toString().padLeft(2, '0')}.${_expireDate!.year}'
                    : 'Срок действия',
                subtitle: _expireDate == null ? 'Нет ограничения' : null,
                leadingIcon: CupertinoIcons.calendar,
                leadingIconBg: c.fill,
                showChevron: true,
                onTap: _pickExpireDate,
              ),
              if (_expireDate != null)
                IosListTile(
                  title: 'Убрать срок',
                  leadingIcon: CupertinoIcons.clear,
                  leadingIconBg: c.fill,
                  onTap: () => setState(() => _expireDate = null),
                ),
            ],
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
            label: 'Создать подписку ($_totalSelected серверов)',
            style: IosButtonStyle.primary,
            leadingIcon: CupertinoIcons.share,
            loading: _loading,
            onPressed: _loading ? null : _create,
          ),

          const SizedBox(height: 12),
          Text(
            'Выберите серверы из любых подписок. Получатель сможет ввести код или вставить ссылку в TeleOpen, Hiddify, v2rayNG и другие клиенты.',
            style: t.textStyles.footnote.copyWith(color: c.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ]),
    );
  }
}

class _CodeCard extends StatelessWidget {
  final String code;
  final String link;
  final VoidCallback onCopyCode;
  final VoidCallback onCopyLink;
  const _CodeCard({required this.code, required this.link, required this.onCopyCode, required this.onCopyLink});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return IosCard(
      padding: const EdgeInsets.all(20),
      radius: IosShapes.radiusXLarge,
      child: Column(children: [
        Text('Код создан!', style: t.textStyles.headline),
        const SizedBox(height: 20),

        
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onCopyCode,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: c.fill,
              borderRadius: IosShapes.continuous(IosShapes.radiusLarge),
            ),
            child: Text(
              code,
              style: t.textStyles.largeTitle.copyWith(
                fontFamily: 'monospace',
                letterSpacing: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Нажми чтобы скопировать',
          style: t.textStyles.caption1.copyWith(color: c.textTertiary)),

        const SizedBox(height: 20),
        Container(height: 0.5, color: c.separator),
        const SizedBox(height: 16),

        
        Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: c.fill,
                borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
              ),
              child: Text(
                link,
                style: t.textStyles.footnote.copyWith(
                  color: c.textSecondary,
                  fontFamily: 'monospace',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onCopyLink,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: c.fill, shape: BoxShape.circle),
              child: Icon(CupertinoIcons.doc_on_clipboard, size: 18, color: c.textPrimary),
            ),
          ),
        ]),
      ]),
    );
  }
}

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

  
  
  String _extractCode(String input) {
    final trimmed = input.trim().toUpperCase();
    
    if (RegExp(r'^[A-Z0-9]{6}$').hasMatch(trimmed)) return trimmed;
    
    final uri = Uri.tryParse(input.trim());
    if (uri != null && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last.toUpperCase();
    }
    
    if (trimmed.length >= 6) return trimmed.substring(trimmed.length - 6);
    return trimmed;
  }

  Future<void> _join() async {
    final input = _ctrl.text.trim();
    if (input.isEmpty) { setState(() => _error = 'Введите код или ссылку'); return; }

    setState(() { _loading = true; _error = null; });

    try {
      final code = _extractCode(input);

      
      
      try {
        final mtUrl = input.contains('/v1/mtproto/')
            ? (input.startsWith('http') ? input : 'http://$input')
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
                content: Text('«$title» добавлена - ${proxies.length} прокси'),
                duration: const Duration(seconds: 2),
              ));
              Navigator.of(context).pop();
              return;
            }
          }
        }
      } catch (_) {
        
      }

      
      final url = input.contains('://') || input.contains(kApiBase.split('://').last)
        ? (input.startsWith('http') ? input : 'http://$input')
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
        content: Text('«$title» добавлена - ${result.nodes.length} серверов'),
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
            placeholder: 'ABC123  или  http://...',
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
          'Введи 6-значный код или вставь ссылку от друга - серверы появятся в твоих подписках.',
          style: t.textStyles.footnote.copyWith(color: c.textTertiary),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }
}

class _MtProtoTab extends StatefulWidget {
  
  final MtProtoProxyGroup? initialGroup;
  const _MtProtoTab({this.initialGroup});

  @override
  State<_MtProtoTab> createState() => _MtProtoTabState();
}

class _MtProtoTabState extends State<_MtProtoTab> {
  final _serverCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();
  final _shareTitleCtrl = TextEditingController();

  
  int _mode = 0;
  String? _error;

  
  
  
  MtProtoProxyGroup? _shareGroup;
  Set<int> _selectedIdx = {}; 

  
  bool _shareLoading = false;
  String? _shareCode;
  String? _shareLink;

  bool get _isShareMode => _shareGroup != null;

  @override
  void initState() {
    super.initState();
    final g = widget.initialGroup;
    if (g != null) {
      _shareGroup = g;
      _shareTitleCtrl.text = g.title;
      
      _selectedIdx = {
        for (var i = 0; i < g.proxies.length; i++)
          if (g.proxies[i].isValid) i
      };
    }
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _portCtrl.dispose();
    _secretCtrl.dispose();
    _linkCtrl.dispose();
    _shareTitleCtrl.dispose();
    super.dispose();
  }

  void _toggleIdx(int i) {
    setState(() {
      if (_selectedIdx.contains(i)) {
        _selectedIdx.remove(i);
      } else {
        _selectedIdx.add(i);
      }
    });
  }

  
  
  
  void _showRenameProxyDialog(BuildContext context, MtProtoProxy proxy) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final ctrl = TextEditingController(text: proxy.name);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgSecondary,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        title: Text('Переименовать', style: t.textStyles.headline),
        content: IosField(
          controller: ctrl,
          label: 'Новое название',
          placeholder: proxy.displayName,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Отмена',
                style:
                    t.textStyles.body.copyWith(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final newName = ctrl.text.trim();
              final updated = proxy.copyWith(name: newName);
              final g = _shareGroup;
              if (g != null) {
                final idx = g.proxies.indexOf(proxy);
                if (idx >= 0) {
                  g.proxies[idx] = updated;
                  AppStateScope.of(context, listen: false)
                      .persistMtProtoGroups();
                }
              }
              Navigator.of(ctx).pop();
              if (mounted) setState(() {});
            },
            child: Text('Сохранить',
                style: t.textStyles.body.copyWith(color: c.textPrimary)),
          ),
        ],
      ),
    );
  }

  
  String _selectedLinksText() {
    final g = _shareGroup;
    if (g == null) return '';
    final sel = <String>[];
    for (var i = 0; i < g.proxies.length; i++) {
      if (!_selectedIdx.contains(i)) continue;
      final p = g.proxies[i];
      if (!p.isValid) continue;
      sel.add(p.buildLink(https: true));
    }
    return sel.join('\n');
  }

  
  Future<void> _createMtProtoCode() async {
    final g = _shareGroup;
    if (g == null) return;

    final title = _shareTitleCtrl.text.trim().isEmpty ? g.title : _shareTitleCtrl.text.trim();

    setState(() { _shareLoading = true; _error = null; _shareCode = null; _shareLink = null; });
    try {
      final selected = <Map<String, String>>[];
      for (var i = 0; i < g.proxies.length; i++) {
        if (!_selectedIdx.contains(i)) continue;
        final p = g.proxies[i];
        if (!p.isValid) continue;
        selected.add({
          'link': p.buildLink(https: true),
          'displayName': p.displayName,
        });
      }
      if (selected.isEmpty) throw Exception('Выберите хотя бы один прокси');

      final resp = await http.post(
        Uri.parse('$kApiBase/v1/mtproto/create'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'title': title, 'proxies': selected}),
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      final code = (jsonDecode(resp.body) as Map)['code'] as String;

      setState(() {
        _shareCode = code;
        _shareLink = '$kApiBase/v1/mtproto/$code';
        _shareLoading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _shareLoading = false; });
    }
  }

  
  MtProtoProxy? _buildProxy() {
    if (_mode == 1) {
      final proxy = MtProtoProxy.tryParse(_linkCtrl.text);
      if (proxy == null) {
        _error = 'Не удалось разобрать ссылку. Поддерживаются tg://proxy и '
            'https://t.me/proxy';
      }
      return proxy;
    }

    final server = _serverCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim());
    final secret = _secretCtrl.text.trim();

    if (server.isEmpty) {
      _error = 'Укажите адрес сервера';
      return null;
    }
    if (port == null || port <= 0 || port > 65535) {
      _error = 'Некорректный порт';
      return null;
    }
    if (secret.isEmpty) {
      _error = 'Укажите secret';
      return null;
    }

    final proxy = MtProtoProxy.mtproto(
      server: server,
      port: port,
      secret: secret,
    );
    if (!proxy.isValid) {
      _error = 'Secret выглядит некорректно. Это должна быть hex-строка '
          '(обычно 32 символа) либо fake-TLS secret.';
      return null;
    }
    return proxy;
  }

  Future<void> _install() async {
    setState(() => _error = null);
    final proxy = _buildProxy();
    if (proxy == null) {
      setState(() {});
      return;
    }
    
    await showInstallMtProtoProxySheet(context, proxy);
  }

  void _save() {
    setState(() => _error = null);
    final proxy = _buildProxy();
    if (proxy == null) {
      setState(() {});
      return;
    }
    AppStateScope.of(context, listen: false).addMtProtoProxy(proxy);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Прокси сохранён в «Мои прокси»'),
      duration: Duration(seconds: 2),
    ));
  }

  void _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;

    
    final proxy = MtProtoProxy.tryParse(text);
    if (proxy != null && proxy.kind == TelegramProxyKind.mtproto) {
      setState(() {
        _mode = 0;
        _serverCtrl.text = proxy.server;
        _portCtrl.text = proxy.port.toString();
        _secretCtrl.text = proxy.secret;
        _linkCtrl.text = text;
        _error = null;
      });
    } else {
      
      setState(() {
        _mode = 1;
        _linkCtrl.text = text;
      });
    }
  }

  
  Widget _buildShareGroup(IosThemeData t, IosColors c) {
    final g = _shareGroup!;
    final validCount = g.proxies.where((p) => p.isValid).length;

    
    if (_shareCode != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        physics: const BouncingScrollPhysics(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _CodeCard(
            code: _shareCode!,
            link: _shareLink!,
            onCopyCode: () {
              Clipboard.setData(ClipboardData(text: _shareCode!));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Скопировано'), duration: Duration(seconds: 1)));
            },
            onCopyLink: () {
              Clipboard.setData(ClipboardData(text: _shareLink!));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Скопировано'), duration: Duration(seconds: 1)));
            },
          ),
          const SizedBox(height: 16),
          IosButton(
            label: 'Создать ещё один',
            style: IosButtonStyle.secondary,
            leadingIcon: CupertinoIcons.refresh,
            onPressed: () => setState(() { _shareCode = null; _shareLink = null; }),
          ),
        ]),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      physics: const BouncingScrollPhysics(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        
        IosListSection(
          header: 'Группа прокси',
          children: [
            IosListTile(
              title: g.title,
              subtitle: '$validCount прокси',
              trailing: Icon(CupertinoIcons.check_mark,
                  size: 18, color: c.textPrimary),
            ),
          ],
        ),

        const SizedBox(height: 12),

        
        IosListSection(
          header: 'Прокси (${_selectedIdx.length} из ${g.proxies.length})',
          children: [
            
            IosListTile(
              title: _selectedIdx.length == g.proxies.length
                  ? 'Снять выделение'
                  : 'Выбрать все',
              leadingIcon: _selectedIdx.length == g.proxies.length
                  ? CupertinoIcons.checkmark_square
                  : CupertinoIcons.square,
              leadingIconBg: c.fill,
              onTap: () => setState(() {
                if (_selectedIdx.length == g.proxies.length) {
                  _selectedIdx.clear();
                } else {
                  _selectedIdx = {
                    for (var i = 0; i < g.proxies.length; i++) i
                  };
                }
              }),
            ),
            for (var i = 0; i < g.proxies.length; i++)
              _buildProxyRow(t, c, g.proxies[i], i),
          ],
        ),

        const SizedBox(height: 12),

        
        IosListSection(
          header: 'Название для получателя',
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: IosField(
                controller: _shareTitleCtrl,
                label: 'Название',
                placeholder: 'Например: Мои прокси',
              ),
            ),
          ],
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
              Icon(CupertinoIcons.exclamationmark_triangle_fill,
                  size: 18, color: c.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_error!,
                    style: t.textStyles.subheadline.copyWith(color: c.red)),
              ),
            ]),
          ),

        IosButton(
          label: 'Создать код',
          style: IosButtonStyle.primary,
          leadingIcon: CupertinoIcons.share,
          loading: _shareLoading,
          onPressed: _shareLoading ? null : _createMtProtoCode,
        ),

        const SizedBox(height: 8),

        IosButton(
          label: 'Добавить прокси вручную',
          style: IosButtonStyle.secondary,
          leadingIcon: CupertinoIcons.add,
          onPressed: () => setState(() {
            _shareGroup = null;
            _error = null;
          }),
        ),

        const SizedBox(height: 12),
        Text(
          'Получатель сможет ввести 6-значный код или открыть ссылку в TeleOpen - и получит копию твоих прокси.',
          style: t.textStyles.footnote.copyWith(color: c.textTertiary),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }

  Widget _buildProxyRow(
      IosThemeData t, IosColors c, MtProtoProxy p, int i) {
    final sel = _selectedIdx.contains(i);
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showRenameProxyDialog(context, p),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.fill,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(CupertinoIcons.pencil,
                size: 17, color: c.textPrimary),
          ),
        ),
        const SizedBox(width: 12),
        
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _toggleIdx(i),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p.displayName,
                        style: t.textStyles.body
                            .copyWith(color: c.textPrimary),
                        overflow: TextOverflow.ellipsis),
                    Text(
                      p.isValid
                          ? '${p.kind.label} · ${p.server}:${p.port}'
                          : '${p.kind.label} · некорректный',
                      style: t.textStyles.footnote.copyWith(
                          color: p.isValid ? c.textSecondary : c.red),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: sel ? c.textPrimary : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: sel ? c.textPrimary : c.textTertiary,
                      width: 1.5),
                ),
                child: sel
                    ? Icon(CupertinoIcons.check_mark,
                        size: 13, color: c.bgSecondary)
                    : null,
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    if (_isShareMode) {
      return _buildShareGroup(t, c);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      physics: const BouncingScrollPhysics(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        
        IosSegment(
          activeIndex: _mode,
          onChanged: (i) => setState(() { _mode = i; _error = null; }),
          items: const [
            IosSegmentItem('По полям'),
            IosSegmentItem('Готовая ссылка'),
          ],
        ),
        const SizedBox(height: 16),

        if (_mode == 0) ...[
          IosListSection(
            header: 'Параметры MTProto Proxy',
            footer: 'Secret - это hex-строка (обычно 32 символа). '
                'Поддерживается и fake-TLS secret (начинается с «ee»).',
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: IosField(
                  controller: _serverCtrl,
                  label: 'Сервер',
                  placeholder: 'proxy.example.com  или  1.2.3.4',
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: IosField(
                  controller: _portCtrl,
                  label: 'Порт',
                  placeholder: '443',
                  keyboardType: TextInputType.number,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: IosField(
                  controller: _secretCtrl,
                  label: 'Secret',
                  placeholder: 'ee0123…  или  hex 32 символа',
                ),
              ),
            ],
          ),
        ] else ...[
          IosCard(
            padding: const EdgeInsets.all(12),
            child: IosField(
              controller: _linkCtrl,
              label: 'Ссылка на прокси',
              placeholder: 'tg://proxy?server=…  или  https://t.me/proxy?…',
              maxLines: 3,
            ),
          ),
        ],

        const SizedBox(height: 12),

        IosButton(
          label: 'Вставить из буфера',
          style: IosButtonStyle.secondary,
          leadingIcon: CupertinoIcons.doc_on_clipboard,
          onPressed: _pasteFromClipboard,
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
              Icon(CupertinoIcons.exclamationmark_triangle_fill,
                  size: 18, color: c.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_error!,
                    style: t.textStyles.subheadline.copyWith(color: c.red)),
              ),
            ]),
          ),

        IosButton(
          label: 'Установить в Telegram',
          style: IosButtonStyle.primary,
          leadingIcon: CupertinoIcons.paperplane_fill,
          onPressed: _install,
        ),

        const SizedBox(height: 8),

        IosButton(
          label: 'Сохранить к себе',
          style: IosButtonStyle.secondary,
          leadingIcon: CupertinoIcons.bookmark,
          onPressed: _save,
        ),

        const SizedBox(height: 12),
        Text(
          'Откроется выбор Telegram-клиента (включая форки). После выбора '
          'Telegram сам покажет окно подключения прокси. VPN при этом не '
          'запускается - прокси работает внутри Telegram.',
          style: t.textStyles.footnote.copyWith(color: c.textTertiary),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }
}

// lib/screens/share_screen.dart
//
// Экран «Поделиться» с тремя вкладками:
//   1) CREATE  — создать 6-значный код из группы серверов, поделиться ссылкой
//   2) JOIN    — ввести код/ссылку и добавить серверы к себе
//   3) MTProto — установить/сохранить MTProto-прокси, поделиться группой
//
// Файл — корень библиотеки share_screen. Сам экран (ShareScreen) ниже, а
// каждая вкладка вынесена в part-файл в lib/screens/share/. Путь файла не
// изменился, поэтому `import '.../share_screen.dart'` в коде продолжает работать.

library share_screen;

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

part 'share/create_tab.dart';
part 'share/join_tab.dart';
part 'share/mtproto_tab.dart';

class ShareScreen extends StatefulWidget {
  /// Если передана группа серверов — сразу открываемся в режиме CREATE.
  final VpnGroup? group;

  /// Если передана MTProto-группа — сразу открываемся на вкладке MTProto
  /// в режиме «Поделиться группой».
  final MtProtoProxyGroup? initialMtProtoGroup;

  const ShareScreen({super.key, this.group, this.initialMtProtoGroup});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  int _tab = 0; // 0=создать, 1=получить, 2=MTProto

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
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(children: [
              Text('Поделиться', style: t.textStyles.largeTitle),
            ]),
          ),

          // Tabs
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

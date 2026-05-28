// lib/widgets/telegram_proxy_sheet.dart
//
// Bottom-sheet выбора Telegram-клиента для установки MTProto Proxy.
//
// Использование:
//   await showInstallMtProtoProxySheet(context, proxy);
//
// Сценарий:
//   1. Сканируем установленные форки Telegram (TelegramProxyService).
//   2. Показываем список — юзер тапает нужный форк.
//   3. Открываем tg://proxy?... именно в этом форке → Telegram показывает
//      штатное окно «Подключить прокси».
//   4. Если форков не нашлось — кнопка «Системный выбор» (chooser Android).

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ios_theme.dart';
import '../models/mtproto_proxy.dart';
import '../logic/telegram_proxy.dart';

/// Показывает шит установки прокси. Возвращает true, если запуск deep-link
/// прошёл успешно (юзер выбрал клиент и он открылся).
Future<bool> showInstallMtProtoProxySheet(
  BuildContext context,
  MtProtoProxy proxy,
) async {
  if (!proxy.isValid) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Некорректные параметры прокси'),
      duration: Duration(seconds: 2),
    ));
    return false;
  }

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TelegramProxySheet(proxy: proxy),
  );
  return result ?? false;
}

class _TelegramProxySheet extends StatefulWidget {
  final MtProtoProxy proxy;
  const _TelegramProxySheet({required this.proxy});

  @override
  State<_TelegramProxySheet> createState() => _TelegramProxySheetState();
}

class _TelegramProxySheetState extends State<_TelegramProxySheet> {
  List<TelegramClient> _clients = [];
  bool _loading = true;
  String? _busyPackage; // package, который сейчас открывается
  String? _error;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() => _loading = true);
    final clients = await TelegramProxyService.detectClients();
    if (!mounted) return;
    setState(() {
      _clients = clients;
      _loading = false;
    });
  }

  Future<void> _openIn(TelegramClient client) async {
    setState(() {
      _busyPackage = client.packageName;
      _error = null;
    });
    try {
      await TelegramProxyService.openInClient(
        widget.proxy,
        client.packageName,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on MtProtoProxyException catch (e) {
      if (!mounted) return;
      setState(() {
        _busyPackage = null;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busyPackage = null;
        _error = 'Не удалось открыть: $e';
      });
    }
  }

  Future<void> _openSystemChooser() async {
    setState(() {
      _busyPackage = '__system__';
      _error = null;
    });
    try {
      await TelegramProxyService.openWithSystemChooser(widget.proxy);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on MtProtoProxyException catch (e) {
      if (!mounted) return;
      setState(() {
        _busyPackage = null;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busyPackage = null;
        _error = 'Не удалось открыть: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final proxy = widget.proxy;

    return Container(
      decoration: BoxDecoration(
        color: c.bgElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Грабер
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: c.fill,
                borderRadius: BorderRadius.circular(3),
              ),
            ),

            // Заголовок
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Column(children: [
                Text('Установить прокси', style: t.textStyles.headline),
                const SizedBox(height: 4),
                Text(
                  '${proxy.kind.label} · ${proxy.server}:${proxy.port}',
                  style: t.textStyles.footnote.copyWith(color: c.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ]),
            ),

            const SizedBox(height: 8),

            // Контент
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _buildBody(t, c),
              ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
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
                          style: t.textStyles.subheadline
                              .copyWith(color: c.red)),
                    ),
                  ]),
                ),
              ),

            // Системный выбор — всегда доступен как fallback
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: IosButton(
                label: 'Системный выбор приложения',
                style: IosButtonStyle.secondary,
                leadingIcon: CupertinoIcons.square_grid_2x2,
                loading: _busyPackage == '__system__',
                onPressed:
                    _busyPackage == null ? _openSystemChooser : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(IosThemeData t, IosColors c) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(children: [
          const CupertinoActivityIndicator(),
          const SizedBox(height: 12),
          Text('Ищем Telegram…',
              style: t.textStyles.footnote.copyWith(color: c.textSecondary)),
        ]),
      );
    }

    if (_clients.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
        child: Column(children: [
          Icon(CupertinoIcons.paperplane,
              size: 40, color: c.textTertiary),
          const SizedBox(height: 12),
          Text(
            'Telegram не найден',
            style: t.textStyles.body.copyWith(color: c.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'Установите Telegram или его форк. Можно также '
            'попробовать системный выбор ниже — вдруг клиент '
            'установлен, но мы его не распознали.',
            style: t.textStyles.footnote.copyWith(color: c.textSecondary),
            textAlign: TextAlign.center,
          ),
        ]),
      );
    }

    return IosListSection(
      header: _clients.length == 1
          ? 'Найден клиент'
          : 'Выберите клиент (${_clients.length})',
      children: _clients.map((client) {
        final busy = _busyPackage == client.packageName;
        return IosListTile(
          leading: _ClientIcon(client: client, color: c),
          title: client.appName,
          subtitle: client.packageName,
          trailing: busy
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CupertinoActivityIndicator(),
                )
              : Icon(CupertinoIcons.chevron_right,
                  size: 16, color: c.textTertiary),
          onTap: _busyPackage == null ? () => _openIn(client) : null,
        );
      }).toList(),
    );
  }
}

/// Иконка приложения: реальная PNG из системы либо заглушка-самолётик.
class _ClientIcon extends StatelessWidget {
  final TelegramClient client;
  final IosColors color;
  const _ClientIcon({required this.client, required this.color});

  @override
  Widget build(BuildContext context) {
    if (client.icon != null && client.icon!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Image.memory(
          client.icon!,
          width: 28,
          height: 28,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color.blue,
          borderRadius: BorderRadius.circular(7),
        ),
        child: const Icon(CupertinoIcons.paperplane_fill,
            size: 15, color: Colors.white),
      );
}

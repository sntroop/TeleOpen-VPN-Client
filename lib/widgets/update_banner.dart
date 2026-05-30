// lib/widgets/update_banner.dart
//
// Баннер «Доступна новая версия» поверх главного экрана + диалог
// со списком изменений и кнопкой «Обновить». Слушает UpdaterService через
// AnimatedBuilder напрямую — не тащим Provider, чтобы не править существующее
// дерево виджетов.

import 'package:flutter/material.dart';

import '../ios_theme.dart';
import '../logic/updater.dart';

/// Узкий баннер сверху. Появляется только если есть available update.
/// Кладите его в начало body главного экрана (HomeScreen).
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final updater = UpdaterService.instance;
    return AnimatedBuilder(
      animation: updater,
      builder: (context, _) {
        final info = updater.available;
        if (info == null) return const SizedBox.shrink();
        final t = IosTheme.of(context);
        final c = t.colors;

        return Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: c.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.blue.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Icon(Icons.system_update_alt, color: c.blue, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Доступна версия ${info.versionName}',
                        style: t.textStyles.headline,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Размер: ${info.sizeHuman}',
                        style: t.textStyles.footnote
                            .copyWith(color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _showDialog(context, info),
                  style: TextButton.styleFrom(
                    foregroundColor: c.blue,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('Подробнее'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDialog(BuildContext context, UpdateInfo info) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => UpdateDialog(info: info),
    );
  }
}

class UpdateDialog extends StatelessWidget {
  final UpdateInfo info;
  const UpdateDialog({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final updater = UpdaterService.instance;

    return AnimatedBuilder(
      animation: updater,
      builder: (context, _) {
        return AlertDialog(
          backgroundColor: c.bgSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'TeleOpen ${info.versionName}',
            style: t.textStyles.title2,
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Размер: ${info.sizeHuman}',
                    style: t.textStyles.footnote
                        .copyWith(color: c.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  if (info.changelog.trim().isNotEmpty) ...[
                    Text('Что нового:', style: t.textStyles.headline),
                    const SizedBox(height: 6),
                    Text(info.changelog, style: t.textStyles.body),
                    const SizedBox(height: 12),
                  ],
                  if (updater.downloading)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Скачивание… ${(updater.progress * 100).toStringAsFixed(0)}%',
                          style: t.textStyles.footnote,
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: updater.progress > 0 ? updater.progress : null,
                            backgroundColor: c.bgPrimary,
                            valueColor: AlwaysStoppedAnimation(c.blue),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  if (updater.error != null && !updater.downloading) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Ошибка: ${updater.error}',
                      style: t.textStyles.footnote.copyWith(color: c.red),
                    ),
                    // Конфликт подписи (смена ключа) — единственный путь это
                    // удалить старую версию и поставить новую заново.
                    if (updater.needsReinstall) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => updater.uninstallForReinstall(),
                          icon: Icon(Icons.delete_outline, color: c.red, size: 18),
                          label: Text(
                            'Удалить старую версию',
                            style: TextStyle(color: c.red),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: c.red.withValues(alpha: 0.5)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'После удаления установите приложение заново — '
                        'это разовая операция из-за обновления ключа подписи.',
                        style: t.textStyles.footnote
                            .copyWith(color: c.textSecondary),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: updater.downloading
                  ? null
                  : () {
                      updater.skip();
                      Navigator.of(context).pop();
                    },
              child: Text(
                'Пропустить',
                style: TextStyle(color: c.textSecondary),
              ),
            ),
            TextButton(
              onPressed: updater.downloading
                  ? null
                  : () => Navigator.of(context).pop(),
              child: Text('Позже', style: TextStyle(color: c.textSecondary)),
            ),
            FilledButton(
              onPressed: updater.downloading
                  ? null
                  : () => updater.downloadAndInstall(),
              style: FilledButton.styleFrom(
                backgroundColor: c.blue,
                // Цвет текста считаем по контрасту с фоном кнопки: в некоторых
                // темах c.blue == белый (0xFFFFFFFF), и захардкоженный белый
                // текст становился невидимым (белое на белом).
                foregroundColor:
                    ThemeData.estimateBrightnessForColor(c.blue) ==
                            Brightness.dark
                        ? Colors.white
                        : Colors.black,
              ),
              child: Text(updater.downloading ? 'Идёт…' : 'Обновить'),
            ),
          ],
        );
      },
    );
  }
}

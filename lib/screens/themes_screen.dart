// lib/screens/themes_screen.dart
//
// Главный экран темы оформления (точка входа из Settings).
// Внутри: текущая тема + кнопка "Создать новую".
// Открывает редактор.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ios_theme.dart';
import '../main.dart';
import '../models/theme.dart';
import '../logic/theme_storage.dart';
import '../logic/market_api.dart';
import '../widgets/color_picker.dart';
import 'theme_gallery_screen.dart';

class ThemesScreen extends StatefulWidget {
  const ThemesScreen({super.key});

  @override
  State<ThemesScreen> createState() => _ThemesScreenState();
}

class _ThemesScreenState extends State<ThemesScreen> {
  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final hasCustom = IosThemeScope.of(context).customTheme != null;
    final currentName = IosThemeScope.of(context).customTheme?.themeName ?? 'Стандартная (тёмная)';

    return Scaffold(
      backgroundColor: c.bgPrimary,
      appBar: AppBar(
        backgroundColor: c.bgPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Темы', style: t.textStyles.headline),
        iconTheme: IconThemeData(color: c.blue),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Текущая тема
          IosCard(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: c.blue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(CupertinoIcons.paintbrush_fill, color: c.bgPrimary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Текущая тема', style: t.textStyles.footnote.copyWith(color: c.textSecondary)),
                  const SizedBox(height: 2),
                  Text(currentName, style: t.textStyles.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              if (hasCustom)
                GestureDetector(
                  onTap: () async {
                    final themeScope = IosThemeScope.of(context);
                    HapticFeedback.lightImpact();
                    await ThemeStorage.clear();
                    if (!mounted) return;
                    themeScope.setCustomTheme(null);
                    setState(() {});
                  },
                  child: Text('Сбросить',
                      style: t.textStyles.subheadline.copyWith(color: c.red)),
                ),
            ]),
          ),

          const SizedBox(height: 16),

          // Галерея
          IosCard(
            padding: EdgeInsets.zero,
            child: _ActionTile(
              icon: CupertinoIcons.square_grid_2x2_fill,
              iconColor: c.blue,
              title: 'Галерея тем',
              subtitle: 'Темы от других пользователей',
              onTap: () async {
                HapticFeedback.lightImpact();
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ThemeGalleryScreen(),
                ));
                if (mounted) setState(() {});
              },
            ),
          ),

          const SizedBox(height: 16),

          // Создать новую
          IosCard(
            padding: EdgeInsets.zero,
            child: _ActionTile(
              icon: CupertinoIcons.plus_circle_fill,
              iconColor: c.green,
              title: 'Создать новую тему',
              subtitle: 'Настрой каждый цвет и радиусы',
              onTap: () async {
                HapticFeedback.lightImpact();
                final draft = UserTheme.newDraft(mode: 'dark');
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ThemeEditorScreen(initial: draft),
                ));
                if (mounted) setState(() {});
              },
            ),
          ),

          const SizedBox(height: 8),

          IosCard(
            padding: EdgeInsets.zero,
            child: _ActionTile(
              icon: CupertinoIcons.sparkles,
              iconColor: c.purple,
              title: 'Создать светлую тему',
              subtitle: 'Стартовать с белого фона',
              onTap: () async {
                HapticFeedback.lightImpact();
                final draft = UserTheme.newDraft(mode: 'light');
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ThemeEditorScreen(initial: draft),
                ));
                if (mounted) setState(() {});
              },
            ),
          ),

          const SizedBox(height: 24),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Тема изменяет все цвета приложения. Можно поделиться готовой темой со всеми пользователями.',
              style: t.textStyles.footnote.copyWith(color: c.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon, required this.iconColor,
    required this.title, required this.subtitle, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(IosShapes.radiusLarge),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.textStyles.body),
              const SizedBox(height: 2),
              Text(subtitle, style: t.textStyles.footnote.copyWith(color: c.textSecondary)),
            ]),
          ),
          Icon(CupertinoIcons.chevron_right, color: c.textTertiary, size: 18),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// РЕДАКТОР ТЕМЫ
// ════════════════════════════════════════════════════════════════════════════

class ThemeEditorScreen extends StatefulWidget {
  final UserTheme initial;
  const ThemeEditorScreen({super.key, required this.initial});

  @override
  State<ThemeEditorScreen> createState() => _ThemeEditorScreenState();
}

class _ThemeEditorScreenState extends State<ThemeEditorScreen> {
  late UserTheme _theme;
  final _nameCtrl = TextEditingController();
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    _theme = widget.initial;
    _nameCtrl.text = _theme.name;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _setColor(String key, Color color) {
    setState(() {
      final c = _theme.colors;
      IosColors next;
      switch (key) {
        case 'bgPrimary':      next = c.copyWith(bgPrimary: color); break;
        case 'bgSecondary':    next = c.copyWith(bgSecondary: color); break;
        case 'bgTertiary':     next = c.copyWith(bgTertiary: color); break;
        case 'bgElevated':     next = c.copyWith(bgElevated: color); break;
        case 'textPrimary':    next = c.copyWith(textPrimary: color); break;
        case 'textSecondary':  next = c.copyWith(textSecondary: color); break;
        case 'textTertiary':   next = c.copyWith(textTertiary: color); break;
        case 'textQuaternary': next = c.copyWith(textQuaternary: color); break;
        case 'blue':           next = c.copyWith(blue: color); break;
        case 'green':          next = c.copyWith(green: color); break;
        case 'red':            next = c.copyWith(red: color); break;
        case 'orange':         next = c.copyWith(orange: color); break;
        case 'yellow':         next = c.copyWith(yellow: color); break;
        case 'purple':         next = c.copyWith(purple: color); break;
        case 'pink':           next = c.copyWith(pink: color); break;
        case 'separator':      next = c.copyWith(separator: color); break;
        case 'fill':           next = c.copyWith(fill: color); break;
        case 'fillSecondary':  next = c.copyWith(fillSecondary: color); break;
        case 'fillTertiary':   next = c.copyWith(fillTertiary: color); break;
        case 'shadow':         next = c.copyWith(shadow: color); break;
        default: return;
      }
      _theme = _theme.copyWith(colors: next);
    });
    // Применяем тему в реальном времени, чтобы редактор сам перекрашивался
    IosThemeScope.of(context).setCustomTheme(_theme.toIosThemeData());
  }

  Future<void> _apply() async {
    HapticFeedback.mediumImpact();
    final theme = _theme.copyWith(name: _nameCtrl.text.trim().isEmpty
        ? 'Моя тема' : _nameCtrl.text.trim());
    await ThemeStorage.save(theme);
    if (!mounted) return;
    IosThemeScope.of(context).setCustomTheme(theme.toIosThemeData());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Тема применена')),
    );
  }

  Future<void> _publish() async {
    final user = AppStateScope.of(context).currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите через Telegram чтобы публиковать темы')),
      );
      return;
    }
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите имя темы')),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _publishing = true);
    try {
      final theme = _theme.copyWith(name: name);
      final id = await MarketApi.themePublish(
        themeId: theme.id,
        theme: theme,
      );
      await ThemeStorage.save(theme);
      if (!mounted) return;
      IosThemeScope.of(context).setCustomTheme(theme.toIosThemeData());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Тема опубликована (id=$id)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return Scaffold(
      backgroundColor: c.bgPrimary,
      appBar: AppBar(
        backgroundColor: c.bgPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Редактор темы', style: t.textStyles.headline),
        iconTheme: IconThemeData(color: c.blue),
        actions: [
          TextButton(
            onPressed: _apply,
            child: Text('Применить',
                style: t.textStyles.body.copyWith(color: c.blue, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Имя
          IosCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Название', style: t.textStyles.footnote.copyWith(color: c.textSecondary)),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _nameCtrl,
                placeholder: 'Моя тема',
                style: t.textStyles.body.copyWith(color: c.textPrimary),
                placeholderStyle: t.textStyles.body.copyWith(color: c.textTertiary),
                decoration: BoxDecoration(
                  color: c.fill,
                  borderRadius: BorderRadius.circular(IosShapes.radiusField),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ]),
          ),

          const SizedBox(height: 16),
          const _SectionHeader('Фоны'),
          _ColorRow(label: 'Главный фон', colorKey: 'bgPrimary', current: _theme.colors.bgPrimary, onPick: _pick),
          _ColorRow(label: 'Карточки', colorKey: 'bgSecondary', current: _theme.colors.bgSecondary, onPick: _pick),
          _ColorRow(label: 'Внутри карточек', colorKey: 'bgTertiary', current: _theme.colors.bgTertiary, onPick: _pick),
          _ColorRow(label: 'Модалки', colorKey: 'bgElevated', current: _theme.colors.bgElevated, onPick: _pick),

          const SizedBox(height: 16),
          const _SectionHeader('Текст'),
          _ColorRow(label: 'Основной', colorKey: 'textPrimary', current: _theme.colors.textPrimary, onPick: _pick),
          _ColorRow(label: 'Вторичный', colorKey: 'textSecondary', current: _theme.colors.textSecondary, onPick: _pick),
          _ColorRow(label: 'Подписи', colorKey: 'textTertiary', current: _theme.colors.textTertiary, onPick: _pick),
          _ColorRow(label: 'Placeholder', colorKey: 'textQuaternary', current: _theme.colors.textQuaternary, onPick: _pick),

          const SizedBox(height: 16),
          const _SectionHeader('Акценты'),
          _ColorRow(label: 'Основной (кнопки)', colorKey: 'blue', current: _theme.colors.blue, onPick: _pick),
          _ColorRow(label: 'Успех / онлайн', colorKey: 'green', current: _theme.colors.green, onPick: _pick),
          _ColorRow(label: 'Удалить / опасность', colorKey: 'red', current: _theme.colors.red, onPick: _pick),
          _ColorRow(label: 'Оранжевый', colorKey: 'orange', current: _theme.colors.orange, onPick: _pick),
          _ColorRow(label: 'Жёлтый (звёзды)', colorKey: 'yellow', current: _theme.colors.yellow, onPick: _pick),
          _ColorRow(label: 'Фиолетовый', colorKey: 'purple', current: _theme.colors.purple, onPick: _pick),
          _ColorRow(label: 'Розовый', colorKey: 'pink', current: _theme.colors.pink, onPick: _pick),

          const SizedBox(height: 16),
          const _SectionHeader('Детали'),
          _ColorRow(label: 'Разделители', colorKey: 'separator', current: _theme.colors.separator, onPick: _pick),
          _ColorRow(label: 'Заливка (поля)', colorKey: 'fill', current: _theme.colors.fill, onPick: _pick),
          _ColorRow(label: 'Заливка вторичная', colorKey: 'fillSecondary', current: _theme.colors.fillSecondary, onPick: _pick),
          _ColorRow(label: 'Заливка третичная', colorKey: 'fillTertiary', current: _theme.colors.fillTertiary, onPick: _pick),
          _ColorRow(label: 'Тень', colorKey: 'shadow', current: _theme.colors.shadow, onPick: _pick),

          const SizedBox(height: 16),
          const _SectionHeader('Радиусы'),
          IosCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(children: [
              _RadiusRow(
                label: 'Кнопки', value: _theme.radii.button, min: 0, max: 30,
                onChanged: (v) => setState(() {
                  _theme = _theme.copyWith(
                    radii: IosRadii(
                      small: _theme.radii.small, medium: _theme.radii.medium,
                      large: _theme.radii.large, xLarge: _theme.radii.xLarge,
                      button: v, field: _theme.radii.field,
                    ),
                  );
                  IosThemeScope.of(context).setCustomTheme(_theme.toIosThemeData());
                }),
              ),
              _RadiusRow(
                label: 'Поля', value: _theme.radii.field, min: 0, max: 30,
                onChanged: (v) => setState(() {
                  _theme = _theme.copyWith(
                    radii: IosRadii(
                      small: _theme.radii.small, medium: _theme.radii.medium,
                      large: _theme.radii.large, xLarge: _theme.radii.xLarge,
                      button: _theme.radii.button, field: v,
                    ),
                  );
                  IosThemeScope.of(context).setCustomTheme(_theme.toIosThemeData());
                }),
              ),
              _RadiusRow(
                label: 'Карточки', value: _theme.radii.large, min: 0, max: 40,
                onChanged: (v) => setState(() {
                  _theme = _theme.copyWith(
                    radii: IosRadii(
                      small: _theme.radii.small, medium: _theme.radii.medium,
                      large: v, xLarge: _theme.radii.xLarge,
                      button: _theme.radii.button, field: _theme.radii.field,
                    ),
                  );
                  IosThemeScope.of(context).setCustomTheme(_theme.toIosThemeData());
                }),
              ),
            ]),
          ),

          const SizedBox(height: 24),

          // Publish button
          IosButton(
            label: _publishing ? 'Публикую…' : 'Опубликовать в галерее',
            onPressed: _publishing ? null : _publish,
          ),

          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Опубликованная тема будет доступна всем пользователям. Тебя укажут как автора.',
              style: t.textStyles.footnote.copyWith(color: c.textTertiary),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _pick(String key, Color current) async {
    final picked = await showColorPicker(context, initial: current);
    if (picked != null) _setColor(key, picked);
  }
}

// ── Маленькие виджеты редактора ───────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(text.toUpperCase(),
          style: t.textStyles.footnote.copyWith(
              color: c.textTertiary, letterSpacing: 0.3)),
    );
  }
}

class _ColorRow extends StatelessWidget {
  final String label;
  final String colorKey;
  final Color current;
  final Future<void> Function(String key, Color current) onPick;

  const _ColorRow({
    required this.label,
    required this.colorKey,
    required this.current,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: IosCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () { HapticFeedback.selectionClick(); onPick(colorKey, current); },
          borderRadius: BorderRadius.circular(IosShapes.radiusLarge),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Expanded(child: Text(label, style: t.textStyles.body)),
              Text(_toHex(current),
                  style: t.textStyles.footnote.copyWith(
                      color: c.textTertiary, fontFamily: 'monospace')),
              const SizedBox(width: 10),
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: current,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.separator, width: 0.5),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  String _toHex(Color c) {
    String h(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    final argb = c.toARGB32();
    final alpha = (argb >> 24) & 0xff;
    final a = alpha == 255 ? '' : h(alpha);
    return '#$a${h((argb >> 16) & 0xff)}${h((argb >> 8) & 0xff)}${h(argb & 0xff)}';
  }
}

class _RadiusRow extends StatelessWidget {
  final String label;
  final double value;
  final double min, max;
  final ValueChanged<double> onChanged;

  const _RadiusRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 90, child: Text(label, style: t.textStyles.body)),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: c.blue,
              inactiveTrackColor: c.fill,
              thumbColor: c.blue,
              overlayColor: c.blue.withValues(alpha: 0.1),
              trackHeight: 3,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min, max: max,
              onChanged: onChanged,
              onChangeStart: (_) => HapticFeedback.selectionClick(),
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text('${value.toStringAsFixed(0)}px',
              textAlign: TextAlign.right,
              style: t.textStyles.footnote.copyWith(
                  color: c.textTertiary, fontFamily: 'monospace')),
        ),
      ]),
    );
  }
}

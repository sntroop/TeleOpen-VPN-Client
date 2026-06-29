// lib/screens/themes_screen.dart
//
// Главный экран темы оформления (точка входа из Settings).
// Внутри: текущая тема + кнопка "Создать новую".
// Открывает редактор.

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ios_theme.dart';
import '../main.dart';
import '../models/theme.dart';
import '../logic/theme_storage.dart';
import '../logic/market_api.dart';
import '../widgets/color_picker.dart';
import 'theme_gallery_screen.dart';

const String _kPrefsAppIconKey = 'app_icon_variant';

class ThemesScreen extends StatefulWidget {
  const ThemesScreen({super.key});

  @override
  State<ThemesScreen> createState() => _ThemesScreenState();
}

class _ThemesScreenState extends State<ThemesScreen> {
  String _appIconVariant = 'default';

  @override
  void initState() {
    super.initState();
    _loadAppIcon();
  }

  Future<void> _loadAppIcon() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() =>
        _appIconVariant = prefs.getString(_kPrefsAppIconKey) ?? 'default');
  }

  Future<void> _setAppIcon(String value) async {
    if (value == _appIconVariant) return;
    HapticFeedback.selectionClick();
    // Берём bridge до await, чтобы не трогать context после паузы.
    final bridge = AppStateScope.of(context).bridge;
    final messenger = ScaffoldMessenger.of(context);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsAppIconKey, value);
    if (!mounted) return;
    setState(() => _appIconVariant = value);
    // Реально переключаем иконку приложения в лаунчере (Android activity-alias).
    final ok = await bridge.setAppIcon(value);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Иконка изменена — лаунчер обновит её в течение пары секунд'
            : 'Не удалось сменить иконку на этом устройстве'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final hasCustom = IosThemeScope.of(context).customTheme != null;
    final currentName = IosThemeScope.of(context).customTheme?.themeName ??
        'Стандартная (тёмная)';

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
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c.blue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(CupertinoIcons.paintbrush_fill,
                    color: c.bgPrimary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Текущая тема',
                          style: t.textStyles.footnote
                              .copyWith(color: c.textSecondary)),
                      const SizedBox(height: 2),
                      Text(currentName,
                          style: t.textStyles.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
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

          const _SectionHeader('Иконка приложения'),
          IosCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final v in _kAppIcons)
                      _AppIconTile(
                        variant: v,
                        selected: _appIconVariant == v.key,
                        onTap: () => _setAppIcon(v.key),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Нажми на иконку — она реально сменится на домашнем экране.',
                  style:
                      t.textStyles.footnote.copyWith(color: c.textTertiary),
                ),
              ],
            ),
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

/// Описание одного варианта иконки приложения.
/// [key] совпадает с ключом в ICON_ALIASES (MainActivity.kt) и с alias'ом в
/// AndroidManifest. [asset] == null — текущая (стандартная) иконка TeleOpen,
/// для которой нет отдельного превью-ассета (показываем плейсхолдер-щит).
class _AppIconVariant {
  final String key;
  final String label;
  final String? asset;
  const _AppIconVariant(this.key, this.label, this.asset);
}

const List<_AppIconVariant> _kAppIcons = [
  _AppIconVariant('default', 'Стандарт', null),
  _AppIconVariant('classic', 'Default', 'assets/icons/Default.png'),
  _AppIconVariant('base', 'Base', 'assets/icons/Base.png'),
  _AppIconVariant('blue', 'Blue', 'assets/icons/Blue.png'),
  _AppIconVariant('green', 'Green', 'assets/icons/Green.png'),
  _AppIconVariant('pink', 'Pink', 'assets/icons/Pink.png'),
  _AppIconVariant('violet', 'Violet', 'assets/icons/Violet.png'),
  _AppIconVariant('white', 'White', 'assets/icons/White.png'),
  _AppIconVariant('yellow', 'Yellow', 'assets/icons/Yellow.png'),
  _AppIconVariant('pixeldef', 'Pixel Def', 'assets/icons/PixelDef.png'),
  _AppIconVariant('pixelstd', 'Pixel Std', 'assets/icons/PixelStandart.png'),
];

class _AppIconTile extends StatelessWidget {
  final _AppIconVariant variant;
  final bool selected;
  final VoidCallback onTap;

  const _AppIconTile({
    required this.variant,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 56,
              height: 56,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: variant.asset == null ? c.blue : c.fill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? c.blue : c.separator,
                  width: selected ? 2 : 0.5,
                ),
              ),
              child: variant.asset == null
                  ? Icon(CupertinoIcons.shield_fill,
                      color: c.bgPrimary, size: 28)
                  : Image.asset(variant.asset!, fit: BoxFit.cover),
            ),
            if (selected)
              Positioned(
                right: -5,
                top: -5,
                child: Container(
                  decoration: BoxDecoration(
                    color: c.bgPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(CupertinoIcons.check_mark_circled_solid,
                      size: 18, color: c.green),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Text(
            variant.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: t.textStyles.footnote.copyWith(
              fontSize: 11,
              color: selected ? c.textPrimary : c.textSecondary,
            ),
          ),
        ]),
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
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
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
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.textStyles.body),
              const SizedBox(height: 2),
              Text(subtitle,
                  style:
                      t.textStyles.footnote.copyWith(color: c.textSecondary)),
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
  Timer? _saveDebounce;
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    _theme = widget.initial;
    _nameCtrl.text = _theme.name;
    _nameCtrl.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    unawaited(_saveCurrentTheme());
    _nameCtrl.removeListener(_onNameChanged);
    _nameCtrl.dispose();
    super.dispose();
  }

  UserTheme _namedTheme() => _theme.copyWith(
        name:
            _nameCtrl.text.trim().isEmpty ? 'Моя тема' : _nameCtrl.text.trim(),
      );

  void _onNameChanged() {
    IosThemeScope.of(context).setCustomTheme(_namedTheme().toIosThemeData());
    _scheduleSave();
  }

  void _setTheme(UserTheme theme) {
    setState(() => _theme = theme);
    IosThemeScope.of(context).setCustomTheme(_namedTheme().toIosThemeData());
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 450), _saveCurrentTheme);
  }

  Future<void> _saveCurrentTheme() async {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    await ThemeStorage.save(_namedTheme());
  }

  void _setColor(String key, Color color) {
    final c = _theme.colors;
    final next = switch (key) {
      'bgPrimary' => c.copyWith(bgPrimary: color),
      'bgSecondary' => c.copyWith(bgSecondary: color),
      'bgTertiary' => c.copyWith(bgTertiary: color),
      'bgElevated' => c.copyWith(bgElevated: color),
      'textPrimary' => c.copyWith(textPrimary: color),
      'textSecondary' => c.copyWith(textSecondary: color),
      'textTertiary' => c.copyWith(textTertiary: color),
      'textQuaternary' => c.copyWith(textQuaternary: color),
      'blue' => c.copyWith(blue: color),
      'green' => c.copyWith(green: color),
      'red' => c.copyWith(red: color),
      'orange' => c.copyWith(orange: color),
      'yellow' => c.copyWith(yellow: color),
      'purple' => c.copyWith(purple: color),
      'pink' => c.copyWith(pink: color),
      'separator' => c.copyWith(separator: color),
      'fill' => c.copyWith(fill: color),
      'fillSecondary' => c.copyWith(fillSecondary: color),
      'fillTertiary' => c.copyWith(fillTertiary: color),
      'shadow' => c.copyWith(shadow: color),
      _ => null,
    };
    if (next == null) return;
    _setTheme(_theme.copyWith(colors: next));
  }

  Future<void> _apply() async {
    HapticFeedback.mediumImpact();
    final theme = _namedTheme();
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
        const SnackBar(
            content: Text('Войдите через Telegram чтобы публиковать темы')),
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
                style: t.textStyles.body
                    .copyWith(color: c.blue, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Имя
          IosCard(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Название',
                  style:
                      t.textStyles.footnote.copyWith(color: c.textSecondary)),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _nameCtrl,
                placeholder: 'Моя тема',
                style: t.textStyles.body.copyWith(color: c.textPrimary),
                placeholderStyle:
                    t.textStyles.body.copyWith(color: c.textTertiary),
                decoration: BoxDecoration(
                  color: c.fill,
                  borderRadius: BorderRadius.circular(IosShapes.radiusField),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ]),
          ),

          const SizedBox(height: 16),
          const _SectionHeader('Фоны'),
          _ColorRow(
              label: 'Главный фон',
              colorKey: 'bgPrimary',
              current: _theme.colors.bgPrimary,
              onPick: _pick),
          _ColorRow(
              label: 'Карточки',
              colorKey: 'bgSecondary',
              current: _theme.colors.bgSecondary,
              onPick: _pick),
          _ColorRow(
              label: 'Внутри карточек',
              colorKey: 'bgTertiary',
              current: _theme.colors.bgTertiary,
              onPick: _pick),
          _ColorRow(
              label: 'Модалки',
              colorKey: 'bgElevated',
              current: _theme.colors.bgElevated,
              onPick: _pick),

          const SizedBox(height: 16),
          const _SectionHeader('Текст'),
          _ColorRow(
              label: 'Основной',
              colorKey: 'textPrimary',
              current: _theme.colors.textPrimary,
              onPick: _pick),
          _ColorRow(
              label: 'Вторичный',
              colorKey: 'textSecondary',
              current: _theme.colors.textSecondary,
              onPick: _pick),
          _ColorRow(
              label: 'Подписи',
              colorKey: 'textTertiary',
              current: _theme.colors.textTertiary,
              onPick: _pick),
          _ColorRow(
              label: 'Placeholder',
              colorKey: 'textQuaternary',
              current: _theme.colors.textQuaternary,
              onPick: _pick),

          const SizedBox(height: 16),
          const _SectionHeader('Акценты'),
          _ColorRow(
              label: 'Основной (кнопки)',
              colorKey: 'blue',
              current: _theme.colors.blue,
              onPick: _pick),
          _ColorRow(
              label: 'Успех / онлайн',
              colorKey: 'green',
              current: _theme.colors.green,
              onPick: _pick),
          _ColorRow(
              label: 'Удалить / опасность',
              colorKey: 'red',
              current: _theme.colors.red,
              onPick: _pick),
          _ColorRow(
              label: 'Оранжевый',
              colorKey: 'orange',
              current: _theme.colors.orange,
              onPick: _pick),
          _ColorRow(
              label: 'Жёлтый (звёзды)',
              colorKey: 'yellow',
              current: _theme.colors.yellow,
              onPick: _pick),
          _ColorRow(
              label: 'Фиолетовый',
              colorKey: 'purple',
              current: _theme.colors.purple,
              onPick: _pick),
          _ColorRow(
              label: 'Розовый',
              colorKey: 'pink',
              current: _theme.colors.pink,
              onPick: _pick),

          const SizedBox(height: 16),
          const _SectionHeader('Детали'),
          _ColorRow(
              label: 'Разделители',
              colorKey: 'separator',
              current: _theme.colors.separator,
              onPick: _pick),
          _ColorRow(
              label: 'Заливка (поля)',
              colorKey: 'fill',
              current: _theme.colors.fill,
              onPick: _pick),
          _ColorRow(
              label: 'Заливка вторичная',
              colorKey: 'fillSecondary',
              current: _theme.colors.fillSecondary,
              onPick: _pick),
          _ColorRow(
              label: 'Заливка третичная',
              colorKey: 'fillTertiary',
              current: _theme.colors.fillTertiary,
              onPick: _pick),
          _ColorRow(
              label: 'Тень',
              colorKey: 'shadow',
              current: _theme.colors.shadow,
              onPick: _pick),

          const SizedBox(height: 16),
          const _SectionHeader('Радиусы'),
          IosCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(children: [
              _RadiusRow(
                label: 'Кнопки',
                value: _theme.radii.button,
                min: 0,
                max: 30,
                onChanged: (v) => _setTheme(
                  _theme.copyWith(
                    radii: IosRadii(
                      small: _theme.radii.small,
                      medium: _theme.radii.medium,
                      large: _theme.radii.large,
                      xLarge: _theme.radii.xLarge,
                      button: v,
                      field: _theme.radii.field,
                    ),
                  ),
                ),
              ),
              _RadiusRow(
                label: 'Поля',
                value: _theme.radii.field,
                min: 0,
                max: 30,
                onChanged: (v) => _setTheme(
                  _theme.copyWith(
                    radii: IosRadii(
                      small: _theme.radii.small,
                      medium: _theme.radii.medium,
                      large: _theme.radii.large,
                      xLarge: _theme.radii.xLarge,
                      button: _theme.radii.button,
                      field: v,
                    ),
                  ),
                ),
              ),
              _RadiusRow(
                label: 'Карточки',
                value: _theme.radii.large,
                min: 0,
                max: 40,
                onChanged: (v) => _setTheme(
                  _theme.copyWith(
                    radii: IosRadii(
                      small: _theme.radii.small,
                      medium: _theme.radii.medium,
                      large: v,
                      xLarge: _theme.radii.xLarge,
                      button: _theme.radii.button,
                      field: _theme.radii.field,
                    ),
                  ),
                ),
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
          style: t.textStyles.footnote
              .copyWith(color: c.textTertiary, letterSpacing: 0.3)),
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
          onTap: () {
            HapticFeedback.selectionClick();
            onPick(colorKey, current);
          },
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
                width: 32,
                height: 32,
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
              min: min,
              max: max,
              onChanged: onChanged,
              onChangeStart: (_) => HapticFeedback.selectionClick(),
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text('${value.toStringAsFixed(0)}px',
              textAlign: TextAlign.right,
              style: t.textStyles.footnote
                  .copyWith(color: c.textTertiary, fontFamily: 'monospace')),
        ),
      ]),
    );
  }
}

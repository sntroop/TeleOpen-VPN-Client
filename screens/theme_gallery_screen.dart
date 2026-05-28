import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ios_theme.dart';
import '../main.dart';
import '../models/theme.dart';
import '../logic/market_api.dart';
import '../logic/theme_storage.dart';
import 'themes_screen.dart' show ThemeEditorScreen;

class ThemeGalleryScreen extends StatefulWidget {
  const ThemeGalleryScreen({super.key});

  @override
  State<ThemeGalleryScreen> createState() => _ThemeGalleryScreenState();
}

class _ThemeGalleryScreenState extends State<ThemeGalleryScreen> {
  List<UserTheme> _items = [];
  bool _loading = true;
  String? _error;
  String _sort = 'popular'; 
  String? _mode; 

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await MarketApi.themesList(sort: _sort, mode: _mode, limit: 50);
      if (!mounted) return;
      setState(() { _items = res.items; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _install(UserTheme theme) async {
    HapticFeedback.mediumImpact();
    try {
      if (theme.id != null) {
        await MarketApi.themeInstall(theme.id!);
      }
    } catch (_) {}
    await ThemeStorage.save(theme);
    if (!mounted) return;
    IosThemeScope.of(context).setCustomTheme(theme.toIosThemeData());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Тема "${theme.name}" применена')),
    );
  }

  Future<void> _delete(UserTheme theme) async {
    final user = AppStateScope.of(context).currentUser;
    if (user == null || theme.id == null) return;

    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Удалить тему?'),
        content: Text('"${theme.name}" будет удалена для всех пользователей.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await MarketApi.themeDelete(themeId: theme.id!);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final user = AppStateScope.of(context).currentUser;

    return Scaffold(
      backgroundColor: c.bgPrimary,
      appBar: AppBar(
        backgroundColor: c.bgPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Галерея тем', style: t.textStyles.headline),
        iconTheme: IconThemeData(color: c.blue),
      ),
      body: Column(children: [
        
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            _Chip(
              label: 'Популярные',
              selected: _sort == 'popular',
              onTap: () { setState(() => _sort = 'popular'); _load(); },
            ),
            const SizedBox(width: 8),
            _Chip(
              label: 'Новые',
              selected: _sort == 'new',
              onTap: () { setState(() => _sort = 'new'); _load(); },
            ),
            const Spacer(),
            _Chip(
              label: 'Все',
              selected: _mode == null,
              onTap: () { setState(() => _mode = null); _load(); },
            ),
            const SizedBox(width: 8),
            _Chip(
              label: '🌙',
              selected: _mode == 'dark',
              onTap: () { setState(() => _mode = 'dark'); _load(); },
            ),
            const SizedBox(width: 8),
            _Chip(
              label: '☀️',
              selected: _mode == 'light',
              onTap: () { setState(() => _mode = 'light'); _load(); },
            ),
          ]),
        ),

        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            color: c.blue,
            child: _loading
                ? Center(child: CupertinoActivityIndicator(color: c.textTertiary))
                : _error != null
                    ? _ErrorView(error: _error!, onRetry: _load)
                    : _items.isEmpty
                        ? _EmptyView()
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (ctx, i) {
                              final theme = _items[i];
                              final mine = user != null &&
                                  theme.authorTelegramId == user.id;
                              return _ThemeListCard(
                                theme: theme,
                                mine: mine,
                                isAdmin: user?.isAdmin == true,
                                onApply: () => _install(theme),
                                onEdit: mine
                                    ? () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => ThemeEditorScreen(
                                              initial: theme),
                                          ),
                                        );
                                        _load();
                                      }
                                    : null,
                                onDelete: (mine || user?.isAdmin == true)
                                    ? () => _delete(theme)
                                    : null,
                              );
                            },
                          ),
          ),
        ),
      ]),
    );
  }
}

class _ThemeListCard extends StatelessWidget {
  final UserTheme theme;
  final bool mine;
  final bool isAdmin;
  final VoidCallback onApply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _ThemeListCard({
    required this.theme,
    required this.mine,
    required this.isAdmin,
    required this.onApply,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    
    final palette = [
      theme.colors.bgPrimary,
      theme.colors.bgSecondary,
      theme.colors.blue,
      theme.colors.green,
      theme.colors.red,
    ];

    final authorLabel = theme.authorFirstName.isNotEmpty
        ? theme.authorFirstName
        : (theme.authorUsername.isNotEmpty ? '@${theme.authorUsername}' : 'без автора');

    return IosCard(
      padding: const EdgeInsets.all(12),
      onTap: onApply,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        
        Container(
          height: 64,
          decoration: BoxDecoration(
            color: theme.colors.bgPrimary,
            borderRadius: BorderRadius.circular(IosShapes.radiusMedium),
            border: Border.all(color: c.separator, width: 0.5),
          ),
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: theme.colors.blue,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 80, height: 8,
                    decoration: BoxDecoration(
                      color: theme.colors.textPrimary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 50, height: 6,
                    decoration: BoxDecoration(
                      color: theme.colors.textSecondary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
            
            Row(children: [
              for (final cc in [theme.colors.green, theme.colors.red, theme.colors.yellow])
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(color: cc, shape: BoxShape.circle),
                  ),
                ),
            ]),
          ]),
        ),

        const SizedBox(height: 10),

        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(theme.name,
                  style: t.textStyles.headline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                '$authorLabel · ${theme.mode == "light" ? "☀️ светлая" : "🌙 тёмная"}',
                style: t.textStyles.footnote.copyWith(color: c.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          if (theme.installsCount > 0) ...[
            Icon(CupertinoIcons.arrow_down_circle, size: 14, color: c.textTertiary),
            const SizedBox(width: 3),
            Text('${theme.installsCount}',
                style: t.textStyles.footnote.copyWith(color: c.textTertiary)),
            const SizedBox(width: 10),
          ],
          if (mine)
            _MiniIcon(icon: CupertinoIcons.pencil, color: c.blue, onTap: onEdit),
          if (onDelete != null) ...[
            const SizedBox(width: 4),
            _MiniIcon(icon: CupertinoIcons.trash, color: c.red, onTap: onDelete),
          ],
        ]),

        const SizedBox(height: 8),

        
        Row(children: [
          for (final cc in palette)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Container(
                width: 18, height: 18,
                decoration: BoxDecoration(
                  color: cc,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: c.separator, width: 0.5),
                ),
              ),
            ),
          const Spacer(),
          GestureDetector(
            onTap: onApply,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: c.blue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(IosShapes.radiusPill),
              ),
              child: Text('Применить',
                  style: t.textStyles.footnote.copyWith(
                      color: c.blue, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _MiniIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _MiniIcon({required this.icon, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c.blue : c.fill,
          borderRadius: BorderRadius.circular(IosShapes.radiusPill),
        ),
        child: Text(label,
            style: t.textStyles.footnote.copyWith(
              color: selected ? c.bgPrimary : c.textPrimary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            )),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return ListView(
      children: [
        const SizedBox(height: 80),
        Icon(CupertinoIcons.paintbrush, size: 56, color: c.textTertiary),
        const SizedBox(height: 16),
        Center(
          child: Text('Пока никто не опубликовал тему',
              style: t.textStyles.body.copyWith(color: c.textSecondary)),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text('Будь первым!',
              style: t.textStyles.footnote.copyWith(color: c.textTertiary)),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    return ListView(
      children: [
        const SizedBox(height: 80),
        Icon(CupertinoIcons.wifi_exclamationmark, size: 48, color: c.red),
        const SizedBox(height: 12),
        Center(
          child: Text('Не удалось загрузить темы',
              style: t.textStyles.body.copyWith(color: c.textSecondary)),
        ),
        const SizedBox(height: 4),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(error,
                textAlign: TextAlign.center,
                style: t.textStyles.footnote.copyWith(color: c.textTertiary)),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: GestureDetector(
            onTap: onRetry,
            child: Text('Повторить',
                style: t.textStyles.body.copyWith(
                    color: c.blue, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

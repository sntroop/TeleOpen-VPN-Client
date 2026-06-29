// lib/state/app_state_groups.dart
//
// VPN-группы: загрузка/сохранение, CRUD над группами и нодами, избранное.
// part of app_state — имеет доступ к приватным полям/методам AppState.

part of 'app_state.dart';

mixin AppStateGroups on AppStateBase {
  /// HIGH-5: ноды (rawUri с паролями) теперь в зашифрованном хранилище, а не в
  /// plain SharedPreferences. Загрузка асинхронна; при первом запуске после
  /// обновления — одноразовая миграция старого ключа 'groups' из prefs.
  Future<void> _loadGroups() async {
    try {
      // Основной путь: файловое хранилище (тянет десятки тысяч нод потоком).
      if (await NodeStore.exists()) {
        groups = await NodeStore.load();
      } else {
        // Миграция с прошлых версий: блоб лежал в secure_storage (а ещё раньше
        // — в plain prefs под 'groups'). Переносим в NodeStore и чистим старое.
        String legacy = '';
        final secure = await SecureStore.readGroups();
        if (secure != null && secure.isNotEmpty) {
          legacy = secure;
        } else {
          final old = prefs.getString('groups');
          if (old != null && old.isNotEmpty) legacy = old;
        }
        groups = VpnGroup.decode(legacy);
        if (groups.isNotEmpty) {
          await NodeStore.save(groups);
        }
        // Старые ключи больше не нужны — освобождаем secure_storage/prefs.
        await SecureStore.deleteGroups();
        await prefs.remove('groups');
      }
      for (final g in groups) {
        // При каждом холодном старте показываем все группы свёрнутыми
        // (состояние раскрытия не персистится — это умолчание для открытия).
        g.isCollapsed = true;
        for (final n in g.nodes) {
          n.isFavorite = favoriteIds.contains(n.id);
          n.groupId = g.id;
        }
      }
    } catch (e, st) {
      // Битьё/несовместимость не должны ронять запуск, но молчаливая потеря всех
      // серверов незаметна — фиксируем причину.
      CrashLog.record(e, st, 'groups.load');
      groups = [];
    }
    // Синхронизируем нативный виджет/тайл со списком после загрузки.
    syncWidgets();
    // Группы готовы — разблокируем ожидающих (deep-link/виджет на холодном старте).
    if (!_groupsReady.isCompleted) _groupsReady.complete();
  }

  @override
  void _saveGroups() {
    // Список нод изменился — инвалидируем кэш отрисовки на главном экране.
    nodesRevision++;
    // Дебаунс записи: пакетные мутации (импорт, обновление подписок) коалесцируем
    // в одну запись на диск. Само шифрование/запись большого файла — в _flushSave.
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _flushSave);
    // Лёгкий список + профили запуска для нативного виджета/тайла (тоже дебаунс).
    syncWidgets();
  }

  Future<void> _flushSave() async {
    // Не запускаем вторую запись поверх текущей — ставим флажок и до-сохраняем
    // после завершения (на случай мутаций во время записи).
    if (_saving) {
      _savePending = true;
      return;
    }
    _saving = true;
    _savePending = false;
    try {
      await NodeStore.save(groups);
    } catch (e, st) {
      CrashLog.record(e, st, 'groups.save');
    } finally {
      _saving = false;
      if (_savePending) {
        _savePending = false;
        // Появились новые изменения во время записи — сохраняем ещё раз.
        // ignore: discarded_futures
        _flushSave();
      }
    }
  }

  // ═════ Избранное ═════

  void toggleFavorite(VpnNode n) {
    n.isFavorite = !n.isFavorite;
    if (n.isFavorite) {
      favoriteIds.add(n.id);
    } else {
      favoriteIds.remove(n.id);
    }
    prefs.setStringList('favorites', favoriteIds.toList());
    // Избранное влияет на фильтр/сортировку — инвалидируем кэш отрисовки.
    nodesRevision++;
    notifyListeners();
  }

  void addMarketGroup({
    required int marketId,
    required String title,
    required List<VpnNode> nodes,
    String? iconUrl,
    String? contactUrl,
    String? description,
  }) {
    final groupId = 'market_$marketId';
    for (final n in nodes) {
      n.groupId = groupId;
      n.isFavorite = favoriteIds.contains(n.id);
    }
    final icon = (iconUrl != null && iconUrl.isNotEmpty) ? iconUrl : null;
    final contact = (contactUrl != null && contactUrl.isNotEmpty) ? contactUrl : null;
    final desc = (description != null && description.isNotEmpty) ? description : null;
    final existing = groups.where((g) => g.id == groupId).cast<VpnGroup?>().firstOrNull;
    if (existing != null) {
      existing.title = title;
      existing.nodes = nodes;
      existing.subtitle = '${nodes.length} серверов · из маркета';
      existing.updatedAt = DateTime.now();
      existing.iconUrl = icon;
      existing.contactUrl = contact;
      existing.description = desc;
    } else {
      groups.add(VpnGroup(
        id: groupId,
        title: title,
        subtitle: '${nodes.length} серверов · из маркета',
        updatedAt: DateTime.now(),
        nodes: nodes,
        iconUrl: icon,
        contactUrl: contact,
        description: desc,
      ));
    }
    _saveGroups();
    notifyListeners();
  }

  void removeGroup(String groupId) {
    groups.removeWhere((g) => g.id == groupId);
    _saveGroups();
    notifyListeners();
  }

  void renameNode(VpnNode n, String newName) {
    n.name = newName;
    if (activeNode?.id == n.id) notifyListeners();
    _saveGroups();
    notifyListeners();
  }

  void removeNode(VpnNode n) {
    if (activeNode?.id == n.id) {
      disconnect();
    }
    favoriteIds.remove(n.id);
    prefs.setStringList('favorites', favoriteIds.toList());
    for (final g in groups) {
      g.nodes.removeWhere((x) => x.id == n.id);
      g.subtitle = '${g.nodes.length} серверов';
    }
    groups.removeWhere((g) => g.nodes.isEmpty);
    _saveGroups();
    notifyListeners();
  }
}

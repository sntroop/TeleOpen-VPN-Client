// lib/state/app_state_groups.dart
//
// VPN-группы: загрузка/сохранение, CRUD над группами и нодами, избранное.
// part of app_state — имеет доступ к приватным полям/методам AppState.

part of 'app_state.dart';

mixin AppStateGroups on AppStateBase {
  void _loadGroups() {
    final s = prefs.getString('groups') ?? '';
    try {
      groups = VpnGroup.decode(s);
      for (final g in groups) {
        for (final n in g.nodes) {
          n.isFavorite = favoriteIds.contains(n.id);
          n.groupId = g.id;
        }
      }
    } catch (e, st) {
      // Битый/несовместимый JSON групп в prefs не должен ронять запуск, но
      // молчаливая потеря всех серверов незаметна — фиксируем причину.
      CrashLog.record(e, st, 'groups.load');
      groups = [];
    }
  }

  @override
  void _saveGroups() {
    prefs.setString('groups', VpnGroup.encode(groups));
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
    notifyListeners();
  }

  void addMarketGroup({
    required int marketId,
    required String title,
    required List<VpnNode> nodes,
  }) {
    final groupId = 'market_$marketId';
    for (final n in nodes) {
      n.groupId = groupId;
      n.isFavorite = favoriteIds.contains(n.id);
    }
    final existing = groups.where((g) => g.id == groupId).cast<VpnGroup?>().firstOrNull;
    if (existing != null) {
      existing.title = title;
      existing.nodes = nodes;
      existing.subtitle = '${nodes.length} серверов · из маркета';
      existing.updatedAt = DateTime.now();
    } else {
      groups.add(VpnGroup(
        id: groupId,
        title: title,
        subtitle: '${nodes.length} серверов · из маркета',
        updatedAt: DateTime.now(),
        nodes: nodes,
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

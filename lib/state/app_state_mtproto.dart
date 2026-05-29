// lib/state/app_state_mtproto.dart
//
// MTProto-прокси и их группы: загрузка/сохранение, CRUD, избранное.
// part of app_state.

part of 'app_state.dart';

mixin AppStateMtProto on AppStateBase {
  void _loadMtProtoGroups() {
    final s = prefs.getString('mtproto_groups') ?? '';
    try {
      mtProtoGroups = MtProtoProxyGroup.decode(s);
    } catch (e, st) {
      // битый/несовместимый JSON в prefs не должен ронять приложение на старте,
      // но фиксируем причину — иначе потеря прокси проходит незаметно.
      CrashLog.record(e, st, 'mtproto.load');
      mtProtoGroups = [];
    }
  }

  void _saveMtProtoGroups() {
    prefs.setString('mtproto_groups', MtProtoProxyGroup.encode(mtProtoGroups));
  }

  /// Добавляет новую группу MTProto-прокси и сохраняет.
  void addMtProtoGroup(MtProtoProxyGroup group) {
    mtProtoGroups.add(group);
    _saveMtProtoGroups();
    notifyListeners();
  }

  /// Удаляет группу по id.
  void removeMtProtoGroup(String groupId) {
    mtProtoGroups.removeWhere((g) => g.id == groupId);
    _saveMtProtoGroups();
    notifyListeners();
  }

  /// Добавляет один прокси в группу (создаёт группу «Мои прокси», если групп нет).
  @override
  void addMtProtoProxy(MtProtoProxy proxy, {String? toGroupId}) {
    MtProtoProxyGroup group;
    if (toGroupId != null) {
      group = mtProtoGroups.firstWhere(
        (g) => g.id == toGroupId,
        orElse: () => _ensureDefaultMtProtoGroup(),
      );
    } else {
      group = _ensureDefaultMtProtoGroup();
    }
    group.proxies.add(proxy);
    _saveMtProtoGroups();
    notifyListeners();
  }

  /// Удаляет прокси из группы. Пустую группу тоже убирает.
  void removeMtProtoProxy(String groupId, MtProtoProxy proxy) {
    final group = mtProtoGroups
        .where((g) => g.id == groupId)
        .cast<MtProtoProxyGroup?>()
        .firstOrNull;
    if (group == null) return;
    group.proxies.remove(proxy);
    if (group.proxies.isEmpty) {
      mtProtoGroups.remove(group);
    }
    _saveMtProtoGroups();
    notifyListeners();
  }

  /// Сохраняет текущее состояние групп (после пинга, переименований и т.п.).
  void persistMtProtoGroups() {
    _saveMtProtoGroups();
    notifyListeners();
  }

  /// Переключает «избранное» у MTProto-прокси. В отличие от VpnNode,
  /// флаг хранится прямо в самой модели прокси (proxy.isFavorite) и
  /// сериализуется вместе с группой.
  void toggleFavoriteMtProto(MtProtoProxy proxy) {
    proxy.isFavorite = !proxy.isFavorite;
    _saveMtProtoGroups();
    notifyListeners();
  }

  MtProtoProxyGroup _ensureDefaultMtProtoGroup() {
    if (mtProtoGroups.isNotEmpty) return mtProtoGroups.first;
    final g = MtProtoProxyGroup(
      id: 'mtproto_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Мои прокси',
      proxies: [],
    );
    mtProtoGroups.add(g);
    return g;
  }
}

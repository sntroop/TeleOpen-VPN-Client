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
      // Холодный старт — все группы свёрнуты (состояние не персистится).
      for (final g in mtProtoGroups) {
        g.isCollapsed = true;
      }
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

  /// Импортирует (или обновляет) группу MTProto-прокси из маркета.
  /// Аналог [addMarketGroup] для VPN: id фиксирован как `market_mtproto_<id>`,
  /// чтобы повторное добавление обновляло существующую группу, а не плодило
  /// дубликаты. `marketGroupId` сохраняем для серверной статистики.
  void addMarketMtProtoGroup({
    required int marketId,
    required String title,
    required List<MtProtoProxy> proxies,
  }) {
    final groupId = 'market_mtproto_$marketId';
    final subtitle = '${proxies.length} прокси · из маркета';
    final existing = mtProtoGroups
        .where((g) => g.id == groupId)
        .cast<MtProtoProxyGroup?>()
        .firstOrNull;
    if (existing != null) {
      existing.title = title;
      existing.subtitle = subtitle;
      existing.marketGroupId = marketId;
      existing.proxies = proxies;
    } else {
      mtProtoGroups.add(MtProtoProxyGroup(
        id: groupId,
        title: title,
        subtitle: subtitle,
        marketGroupId: marketId,
        proxies: proxies,
      ));
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

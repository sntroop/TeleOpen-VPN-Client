// lib/state/app_state_subscriptions.dart
//
// Подписки (импорт по URL, обновление) и ручное добавление нод/прокси.
// part of app_state.

part of 'app_state.dart';

mixin AppStateSubscriptions on AppStateBase {
  Future<String?> addSubscription({required String url, String? title}) async {
    final result = await SubscriptionLoader.load(url);
    if (result.error != null) return result.error;
    if (result.nodes.isEmpty) return 'Не найдено серверов';

    final groupTitle = (title?.isNotEmpty == true)
        ? title!
        : (result.groupTitle.isNotEmpty
            ? result.groupTitle
            : (Uri.tryParse(url)?.host.isNotEmpty == true
                ? Uri.parse(url).host
                : 'Sub ${groups.length + 1}'));

    final groupId = 'sub_${DateTime.now().millisecondsSinceEpoch}';
    for (final n in result.nodes) {
      n.groupId = groupId;
      n.isFavorite = favoriteIds.contains(n.id);
    }
    final group = VpnGroup(
      id: groupId,
      title: groupTitle,
      subtitle: '${result.nodes.length} серверов',
      sourceUrl: url,
      updatedAt: DateTime.now(),
      nodes: result.nodes,
      trafficUpload:   result.userInfo['upload'],
      trafficDownload: result.userInfo['download'],
      trafficTotal:    result.userInfo['total'],
      trafficExpire:   result.userInfo['expire'],
      description:     result.announce,
    );
    groups.add(group);
    _saveGroups();
    notifyListeners();
    return null;
  }

  Future<String?> refreshSubscription(VpnGroup g) async {
    if (g.sourceUrl == null) return 'У группы нет URL подписки';
    final result = await SubscriptionLoader.load(g.sourceUrl!);
    if (result.error != null) return result.error;
    for (final n in result.nodes) {
      n.groupId = g.id;
      n.isFavorite = favoriteIds.contains(n.id);
    }
    g.nodes = result.nodes;
    g.subtitle = '${result.nodes.length} серверов';
    g.updatedAt = DateTime.now();
    if (result.userInfo.isNotEmpty) {
      g.trafficUpload   = result.userInfo['upload'];
      g.trafficDownload = result.userInfo['download'];
      g.trafficTotal    = result.userInfo['total'];
      g.trafficExpire   = result.userInfo['expire'];
    }
    if (result.announce != null) {
      g.description = result.announce;
    }
    _saveGroups();
    notifyListeners();
    return null;
  }

  String? addManualNode(String uri) {
    final cleaned = uri.trim();
    final lower = cleaned.toLowerCase();

    // MTProto / SOCKS Telegram proxy — диспетчим отдельно
    if (lower.startsWith('tg://') ||
        lower.startsWith('https://t.me/') ||
        lower.startsWith('http://t.me/') ||
        lower.startsWith('t.me/')) {
      final proxy = MtProtoProxy.tryParse(cleaned);
      if (proxy == null) return 'Не удалось распарсить MTProto-ссылку';
      addMtProtoProxy(proxy);
      return null;
    }

    // Обычные VPN
    final node = parseUri(cleaned);
    if (node == null) return 'Не удалось распарсить URI';
    const groupId = 'manual';
    var group = groups.where((g) => g.id == groupId).cast<VpnGroup?>().firstOrNull;
    if (group == null) {
      group = VpnGroup(id: groupId, title: 'Мои серверы', nodes: []);
      groups.add(group);
    }
    if (group.nodes.any((n) => n.rawUri == node.rawUri)) {
      return 'Такой сервер уже добавлен';
    }
    node.groupId = groupId;
    node.isFavorite = favoriteIds.contains(node.id);
    group.nodes.add(node);
    group.subtitle = '${group.nodes.length} серверов';
    _saveGroups();
    notifyListeners();
    return null;
  }
}

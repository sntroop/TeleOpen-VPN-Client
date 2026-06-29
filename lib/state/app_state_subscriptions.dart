// lib/state/app_state_subscriptions.dart
//
// Подписки (импорт по URL, обновление) и ручное добавление нод/прокси.
// part of app_state.

part of 'app_state.dart';

/// Итог добавления живой ссылки teleopen://.
/// [error] != null — подписка не добавлена (текст для пользователя).
/// [rejected] — продавец отозвал/просрочил подписку (не сетевая ошибка).
class TeleopenAddResult {
  final String? error;
  final String? title;
  final int nodeCount;
  final bool rejected;
  const TeleopenAddResult({
    this.error,
    this.title,
    this.nodeCount = 0,
    this.rejected = false,
  });
  bool get ok => error == null;
}

mixin AppStateSubscriptions on AppStateBase {
  /// Очередь не показанных рассылок продавца (Фаза 4). Наполняется
  /// [pullTeleopenMetas], опустошается UI ([maybeShowBroadcasts]). Дедуп показа
  /// — на бэке (broadcast_seen по did), здесь лишь не плодим дубли в сессии.
  final List<TeleOpenBroadcast> pendingBroadcasts = [];

  /// Резолвит живую ссылку teleopen:// и добавляет её как подписку.
  /// Делает один сетевой проход: тянет богатый JSON (бренд/renew/статус),
  /// отсекает banned/expired, затем грузит sub-формат через addSubscription.
  /// Используется и экраном добавления, и обработчиком deep links.
  Future<TeleopenAddResult> addTeleopenLink(TeleOpenLink link) async {
    final dq = await DeviceId.query();
    final meta = await fetchTeleOpenMeta(link, deviceQuery: dq);
    final blocked = _teleopenStatusError(meta.status);
    if (blocked != null) {
      return TeleopenAddResult(rejected: true, error: blocked);
    }
    final err = await addSubscription(
      url: '${link.subUrl}&$dq',
      title: (meta.brandName?.isNotEmpty == true) ? meta.brandName : null,
      renewUrl: meta.renewUrl,
      brandColor: meta.brandColor,
    );
    if (err != null) return TeleopenAddResult(error: err);
    // addSubscription при успехе добавляет группу в конец списка.
    final g = groups.last;
    return TeleopenAddResult(title: g.title, nodeCount: g.nodes.length);
  }

  /// Человекочитаемая причина, если статус подписки блокирует подключение.
  /// null — статус ок (active/trial/неизвестно).
  String? _teleopenStatusError(String? status) {
    switch (status) {
      case 'banned':
        return 'Подписка отозвана продавцом.';
      case 'expired':
        return 'Срок подписки истёк.';
      case 'frozen':
        return 'Подписка заморожена продавцом.';
      case 'exhausted':
        return 'Исчерпан лимит трафика подписки.';
      case 'device_limit':
        return 'Превышен лимит устройств для этой подписки.';
      default:
        return null;
    }
  }

  Future<String?> addSubscription({
    required String url,
    String? title,
    String? renewUrl,
    String? brandColor,
    String? description,
  }) async {
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
      description:     (description?.isNotEmpty == true)
          ? description
          : result.announce,
      renewUrl:        renewUrl,
      brandColor:      brandColor,
    );
    groups.add(group);
    _saveGroups();
    notifyListeners();
    return null;
  }

  Future<String?> refreshSubscription(VpnGroup g) async {
    // Подписки из маркета не имеют sourceUrl — обновляются по market-id.
    if (g.sourceUrl == null || g.sourceUrl!.isEmpty) {
      if (!g.id.startsWith('market_')) return 'У группы нет URL подписки';
      final err = await _refreshMarketGroup(g);
      if (err == null) {
        _saveGroups();
        notifyListeners();
      }
      return err;
    }
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

  /// Обновляет подписку из маркета по её market-id (group.id = "market_<id>").
  /// Возвращает текст ошибки или null при успехе. Не дёргает _saveGroups/
  /// notifyListeners — это делает вызывающий (refreshSubscription/refreshAll).
  Future<String?> _refreshMarketGroup(VpnGroup g) async {
    final marketId = int.tryParse(g.id.substring('market_'.length));
    if (marketId == null) return 'Некорректный id подписки';
    // Требует валидный JWT; без логина вернётся 401.
    final res = await MarketApi.get(marketId);
    final nodes = <VpnNode>[];
    for (final mn in res.nodes) {
      final n = parseUri(mn.uri);
      if (n != null) {
        n.groupId = g.id;
        n.isFavorite = favoriteIds.contains(n.id);
        nodes.add(n);
      }
    }
    if (nodes.isEmpty) return 'Не удалось обновить серверы';
    g.nodes = nodes;
    g.subtitle = '${nodes.length} серверов · из маркета';
    g.updatedAt = DateTime.now();
    return null;
  }

  /// Фоновое обновление всех подписок (URL и из маркета). Ошибки отдельных
  /// групп глушим — это автоматический фон, он не должен ломать UI.
  /// Вызывается по таймеру (AppState.reconfigureSubscriptionAutoUpdate).
  @override
  Future<void> refreshAllSubscriptions() async {
    for (final g in List<VpnGroup>.from(groups)) {
      try {
        if ((g.sourceUrl != null && g.sourceUrl!.isNotEmpty) ||
            g.id.startsWith('market_')) {
          await refreshSubscription(g);
        }
      } catch (_) {
        // отдельная группа не обновилась — пропускаем
      }
    }
    _saveGroups();
    notifyListeners();
    prefs.setInt('last_sub_refresh', DateTime.now().millisecondsSinceEpoch);
  }

  /// Подтягивает «живую» json-мету teleopen-подписок: освежает бренд/renew_url
  /// (продавец мог сменить) и собирает таргетированные рассылки в очередь
  /// [pendingBroadcasts]. Обычный refresh идёт по format=sub и этих полей не
  /// видит, поэтому ремаркетинг тянем отдельным проходом по format=json.
  /// Тихо игнорирует сетевые сбои — это фон.
  Future<void> pullTeleopenMetas() async {
    final seen = pendingBroadcasts.map((b) => b.id).toSet();
    var changed = false;
    for (final g in List<VpnGroup>.from(groups)) {
      final url = g.sourceUrl;
      if (url == null || url.isEmpty) continue;
      final link = parseTeleOpenLink(url);
      if (link == null) continue;
      try {
        final dq = await DeviceId.query();
        final meta = await fetchTeleOpenMeta(link, deviceQuery: dq);
        if (meta.brandColor?.isNotEmpty == true && meta.brandColor != g.brandColor) {
          g.brandColor = meta.brandColor;
          changed = true;
        }
        if (meta.renewUrl?.isNotEmpty == true && meta.renewUrl != g.renewUrl) {
          g.renewUrl = meta.renewUrl;
          changed = true;
        }
        final bc = meta.broadcast;
        if (bc != null && seen.add(bc.id)) {
          pendingBroadcasts.add(bc);
          changed = true;
        }
      } catch (_) {
        // фон — отдельная подписка не критична
      }
    }
    if (changed) {
      _saveGroups();
      notifyListeners();
    }
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

  /// Массовое добавление узлов (импорт из файла/буфера).
  ///
  /// В отличие от [addManualNode], который шифрует и пишет ВЕСЬ список групп на
  /// диск и дёргает notifyListeners НА КАЖДЫЙ узел — на тысячах конфигов это
  /// O(n²) сериализация + тысячи перерисовок UI, что вешает главный поток и
  /// роняет приложение. Здесь всё парсится и дедуплицируется в памяти, а запись
  /// на диск и уведомление слушателей происходят ОДИН раз в конце.
  ///
  /// Парсинг разбит на чанки с уступкой event-loop'у (`Future.delayed(zero)`)
  /// каждые [_bulkChunk] элементов: на десятках тысяч URI синхронный цикл (~1-2с)
  /// повесил бы главный поток и вызвал ANR. [onProgress] позволяет показать
  /// «Обработано N / M».
  ///
  /// Возвращает (added: добавлено, failed: не распарсилось). Дубликаты не
  /// считаются ошибкой и молча пропускаются.
  static const int _bulkChunk = 1000;

  Future<({int added, int failed})> addManualNodesBulk(
    Iterable<String> uris, {
    void Function(int done, int total)? onProgress,
  }) async {
    final list = uris is List<String> ? uris : uris.toList();
    final total = list.length;

    const groupId = 'manual';
    var group = groups.where((g) => g.id == groupId).cast<VpnGroup?>().firstOrNull;
    if (group == null) {
      group = VpnGroup(id: groupId, title: 'Мои серверы', nodes: []);
      groups.add(group);
    }
    // rawUri уже добавленных — Set даёт O(1) дедуп вместо O(n) перебора на узел.
    final existing = group.nodes.map((n) => n.rawUri).toSet();

    int added = 0, failed = 0;
    bool vpnChanged = false;
    for (var i = 0; i < total; i++) {
      final cleaned = list[i].trim();
      if (cleaned.isNotEmpty) {
        final lower = cleaned.toLowerCase();
        // MTProto / Telegram-proxy — редкий случай в массовом импорте; идём через
        // существующий путь (он сам сохранит/уведомит).
        if (lower.startsWith('tg://') ||
            lower.startsWith('https://t.me/') ||
            lower.startsWith('http://t.me/') ||
            lower.startsWith('t.me/')) {
          final proxy = MtProtoProxy.tryParse(cleaned);
          if (proxy == null) {
            failed++;
          } else {
            addMtProtoProxy(proxy);
            added++;
          }
        } else {
          // Обычный VPN — парсим и копим в памяти, без записи на диск.
          final node = parseUri(cleaned);
          if (node == null) {
            failed++;
          } else if (existing.add(node.rawUri)) {
            // не дубликат
            node.groupId = groupId;
            node.isFavorite = favoriteIds.contains(node.id);
            group.nodes.add(node);
            vpnChanged = true;
            added++;
          }
        }
      }

      // Уступаем поток и репортим прогресс каждые _bulkChunk итераций.
      if ((i + 1) % _bulkChunk == 0) {
        onProgress?.call(i + 1, total);
        await Future<void>.delayed(Duration.zero);
      }
    }
    onProgress?.call(total, total);

    if (vpnChanged) {
      group.subtitle = '${group.nodes.length} серверов';
      _saveGroups();
      notifyListeners();
    }
    return (added: added, failed: failed);
  }
}

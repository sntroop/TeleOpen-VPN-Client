// lib/models/market.dart
//
// Модели API маркетплейса 1-в-1 с бэкендом FastAPI.

class TgUser {
  final int id;
  final String username;
  final String firstName;
  final String lastName;
  final String photoUrl;
  final bool isAdmin;

  TgUser({
    required this.id,
    this.username = '',
    this.firstName = '',
    this.lastName = '',
    this.photoUrl = '',
    this.isAdmin = false,
  });

  String get displayName {
    if (firstName.isNotEmpty) return firstName;
    if (username.isNotEmpty) return '@$username';
    return 'User $id';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'first_name': firstName,
        'last_name': lastName,
        'photo_url': photoUrl,
        'is_admin': isAdmin,
      };

  factory TgUser.fromJson(Map<String, dynamic> j) => TgUser(
        id: (j['id'] as num).toInt(),
        username: j['username'] ?? '',
        firstName: j['first_name'] ?? '',
        lastName: j['last_name'] ?? '',
        photoUrl: j['photo_url'] ?? '',
        isAdmin: j['is_admin'] == true,
      );
}

class MarketAuthor {
  final String username;
  final String firstName;
  final String photoUrl;

  MarketAuthor({this.username = '', this.firstName = '', this.photoUrl = ''});

  String get displayName {
    if (firstName.isNotEmpty) return firstName;
    if (username.isNotEmpty) return '@$username';
    return 'Аноним';
  }

  factory MarketAuthor.fromJson(Map<String, dynamic> j) => MarketAuthor(
        username: j['username'] ?? '',
        firstName: j['first_name'] ?? '',
        photoUrl: j['photo_url'] ?? '',
      );
}

class MarketReview {
  final int rating;
  final String comment;
  final DateTime createdAt;
  final MarketAuthor author;

  MarketReview({
    required this.rating,
    required this.comment,
    required this.createdAt,
    required this.author,
  });

  factory MarketReview.fromJson(Map<String, dynamic> j) => MarketReview(
        rating: (j['rating'] as num).toInt(),
        comment: j['comment'] ?? '',
        createdAt: DateTime.tryParse(j['created_at'] ?? '') ?? DateTime.now(),
        author:
            MarketAuthor.fromJson((j['author'] as Map).cast<String, dynamic>()),
      );
}

/// Карточка подписки в списке маркетплейса
class MarketItem {
  final int id;
  final String name;
  final String description;
  final String iconUrl;
  final List<String> tags;
  final int nodesCount;
  final int getsCount;
  final int activeSessions;
  final double ratingAvg;
  final int ratingCount;
  final DateTime createdAt;
  final MarketAuthor author;
  final TeleOpenBadge? teleOpenBadge;
  final String contactUrl;

  /// Тип группы: 'vpn' (VLESS/Trojan/...) либо 'mtproto' (Telegram-прокси).
  final String groupKind;

  /// Платная подписка: цена и лимиты на покупателя (null = безлимит).
  final bool isPaid;
  final double? priceRub;
  final int? paidDurationDays;
  final int? paidTrafficGb;
  final int? paidDeviceLimit;

  /// Тарифная сетка (срок → цена). Для старых публикаций бэк сам заворачивает
  /// одиночную цену в один тариф.
  final List<MarketTariff> tariffs;

  /// Цена за каждое устройство сверх первого (null/0 = докупка недоступна).
  final double? extraDevicePriceRub;

  /// Цена докупки трафика, ₽ за 1 ГБ (null/0 = докупка недоступна).
  final double? extraGbPriceRub;

  MarketItem({
    required this.id,
    required this.name,
    required this.description,
    required this.iconUrl,
    required this.tags,
    required this.nodesCount,
    required this.getsCount,
    required this.activeSessions,
    required this.ratingAvg,
    required this.ratingCount,
    required this.createdAt,
    required this.author,
    this.teleOpenBadge,
    this.contactUrl = '',
    this.groupKind = 'vpn',
    this.isPaid = false,
    this.priceRub,
    this.paidDurationDays,
    this.paidTrafficGb,
    this.paidDeviceLimit,
    this.tariffs = const [],
    this.extraDevicePriceRub,
    this.extraGbPriceRub,
  });

  /// true, если это группа MTProto-прокси.
  bool get isMtProto => groupKind == 'mtproto';

  /// Самая низкая цена по тарифам — для бейджа «от N ₽».
  double? get minPriceRub {
    if (tariffs.isEmpty) return priceRub;
    return tariffs.map((t) => t.priceRub).reduce((a, b) => a < b ? a : b);
  }

  factory MarketItem.fromJson(Map<String, dynamic> j) => MarketItem(
        id: (j['id'] as num).toInt(),
        name: j['name'] ?? '',
        description: j['description'] ?? '',
        iconUrl: j['icon_url'] ?? '',
        tags: ((j['tags'] as List?) ?? []).map((e) => e.toString()).toList(),
        nodesCount: (j['nodes_count'] as num?)?.toInt() ?? 0,
        getsCount: (j['gets_count'] as num?)?.toInt() ?? 0,
        activeSessions: (j['active_sessions'] as num?)?.toInt() ?? 0,
        ratingAvg: (j['rating_avg'] as num?)?.toDouble() ?? 0.0,
        ratingCount: (j['rating_count'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(j['created_at'] ?? '') ?? DateTime.now(),
        author:
            MarketAuthor.fromJson((j['author'] as Map).cast<String, dynamic>()),
        teleOpenBadge: TeleOpenBadgeExt.fromApi(j['teleopen_badge'] as String?),
        contactUrl: (j['contact_url'] as String?) ?? '',
        groupKind: (j['group_kind'] as String?) ?? 'vpn',
        isPaid: j['is_paid'] == true,
        priceRub: (j['price_rub'] as num?)?.toDouble(),
        paidDurationDays: (j['paid_duration_days'] as num?)?.toInt(),
        paidTrafficGb: (j['paid_traffic_gb'] as num?)?.toInt(),
        paidDeviceLimit: (j['paid_device_limit'] as num?)?.toInt(),
        tariffs: ((j['tariffs'] as List?) ?? [])
            .map((e) =>
                MarketTariff.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        extraDevicePriceRub: (j['extra_device_price_rub'] as num?)?.toDouble(),
        extraGbPriceRub: (j['extra_gb_price_rub'] as num?)?.toDouble(),
      );
}

/// Тариф платной подписки: срок в днях + цена за период.
class MarketTariff {
  final int days;
  final double priceRub;

  MarketTariff({required this.days, required this.priceRub});

  factory MarketTariff.fromJson(Map<String, dynamic> j) => MarketTariff(
        days: (j['days'] as num?)?.toInt() ?? 0,
        priceRub: (j['price_rub'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {'days': days, 'price_rub': priceRub};

  /// «30 дней», «1 год» и т.п.
  String get periodLabel {
    if (days % 365 == 0) {
      final y = days ~/ 365;
      return y == 1 ? '1 год' : '$y ${y < 5 ? "года" : "лет"}';
    }
    if (days % 30 == 0) {
      final m = days ~/ 30;
      if (m == 1) return '1 месяц';
      if (m < 5) return '$m месяца';
      return '$m месяцев';
    }
    final mod10 = days % 10, mod100 = days % 100;
    if (mod10 == 1 && mod100 != 11) return '$days день';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return '$days дня';
    }
    return '$days дней';
  }
}

/// Детальная страница подписки = MarketItem + отзывы + моё ревью + speed_15m
class MarketDetail extends MarketItem {
  final List<MarketReview> reviews;
  final MarketReview? myReview;
  final SpeedStats speed15m;

  /// Моя покупка этой платной подписки (null — не куплено).
  final MarketPurchase? myPurchase;

  MarketDetail({
    required super.id,
    required super.name,
    required super.description,
    required super.iconUrl,
    required super.tags,
    required super.nodesCount,
    required super.getsCount,
    required super.activeSessions,
    required super.ratingAvg,
    required super.ratingCount,
    required super.createdAt,
    required super.author,
    super.teleOpenBadge,
    super.contactUrl,
    super.groupKind,
    super.isPaid,
    super.priceRub,
    super.paidDurationDays,
    super.paidTrafficGb,
    super.paidDeviceLimit,
    super.tariffs,
    super.extraDevicePriceRub,
    super.extraGbPriceRub,
    required this.reviews,
    required this.myReview,
    required this.speed15m,
    this.myPurchase,
  });

  factory MarketDetail.fromJson(Map<String, dynamic> j) {
    final base = MarketItem.fromJson(j);
    final my = j['my_review'];
    final myPur = j['my_purchase'];
    return MarketDetail(
      id: base.id,
      name: base.name,
      description: base.description,
      iconUrl: base.iconUrl,
      tags: base.tags,
      nodesCount: base.nodesCount,
      getsCount: base.getsCount,
      activeSessions: base.activeSessions,
      ratingAvg: base.ratingAvg,
      ratingCount: base.ratingCount,
      createdAt: base.createdAt,
      author: base.author,
      teleOpenBadge: base.teleOpenBadge,
      contactUrl: base.contactUrl,
      groupKind: base.groupKind,
      isPaid: base.isPaid,
      priceRub: base.priceRub,
      paidDurationDays: base.paidDurationDays,
      paidTrafficGb: base.paidTrafficGb,
      paidDeviceLimit: base.paidDeviceLimit,
      tariffs: base.tariffs,
      extraDevicePriceRub: base.extraDevicePriceRub,
      extraGbPriceRub: base.extraGbPriceRub,
      reviews: ((j['reviews'] as List?) ?? [])
          .map((e) => MarketReview.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      myReview: my == null
          ? null
          : MarketReview(
              rating: (my['rating'] as num).toInt(),
              comment: my['comment'] ?? '',
              createdAt: DateTime.now(),
              author: MarketAuthor(),
            ),
      speed15m: SpeedStats.fromJson(
          (j['speed_15m'] as Map?)?.cast<String, dynamic>() ?? {}),
      myPurchase: myPur == null
          ? null
          : MarketPurchase.fromJson((myPur as Map).cast<String, dynamic>()),
    );
  }
}

class SpeedStats {
  final int uploadBytes;
  final int downloadBytes;
  final int activeUsers;

  SpeedStats(
      {this.uploadBytes = 0, this.downloadBytes = 0, this.activeUsers = 0});

  factory SpeedStats.fromJson(Map<String, dynamic> j) => SpeedStats(
        uploadBytes: (j['upload_bytes'] as num?)?.toInt() ?? 0,
        downloadBytes: (j['download_bytes'] as num?)?.toInt() ?? 0,
        activeUsers: (j['active_users'] as num?)?.toInt() ?? 0,
      );
}

/// Live stats — лёгкий эндпоинт для частого poll'инга
class LiveStats {
  final int groupId;
  final int activeUsers15m;
  final int totalSessions;
  final int uploadBytes15m;
  final int downloadBytes15m;
  final int brokenNodesCount;

  LiveStats({
    required this.groupId,
    required this.activeUsers15m,
    required this.totalSessions,
    required this.uploadBytes15m,
    required this.downloadBytes15m,
    required this.brokenNodesCount,
  });

  factory LiveStats.fromJson(Map<String, dynamic> j) => LiveStats(
        groupId: (j['group_id'] as num).toInt(),
        activeUsers15m: (j['active_users_15m'] as num?)?.toInt() ?? 0,
        totalSessions: (j['total_sessions'] as num?)?.toInt() ?? 0,
        uploadBytes15m: (j['upload_bytes_15m'] as num?)?.toInt() ?? 0,
        downloadBytes15m: (j['download_bytes_15m'] as num?)?.toInt() ?? 0,
        brokenNodesCount: (j['broken_nodes_count'] as num?)?.toInt() ?? 0,
      );
}

/// Здоровье узлов подписки (битые/живые)
class NodeHealth {
  final String uriHash;
  final int reports;
  final bool broken;

  NodeHealth(
      {required this.uriHash, required this.reports, required this.broken});

  factory NodeHealth.fromJson(Map<String, dynamic> j) => NodeHealth(
        uriHash: j['uri_hash'] ?? '',
        reports: (j['reports'] as num?)?.toInt() ?? 0,
        broken: j['broken'] == true,
      );
}

/// Узел из /market/get — uri + хэш (хэш нужен для report_node)
class MarketNode {
  final String uri;
  final String uriHash;
  MarketNode({required this.uri, required this.uriHash});

  factory MarketNode.fromJson(Map<String, dynamic> j) => MarketNode(
        uri: j['uri'] ?? '',
        uriHash: j['uri_hash'] ?? '',
      );
}

class MarketItemForAuthor extends MarketItem {
  final List<MarketReview> recentReviews;
  MarketItemForAuthor({
    required super.id,
    required super.name,
    required super.description,
    required super.iconUrl,
    required super.tags,
    required super.nodesCount,
    required super.getsCount,
    required super.activeSessions,
    required super.ratingAvg,
    required super.ratingCount,
    required super.createdAt,
    required super.author,
    super.teleOpenBadge,
    super.contactUrl,
    super.groupKind,
    required this.recentReviews,
  });

  factory MarketItemForAuthor.fromJson(Map<String, dynamic> j) {
    final base = MarketItem.fromJson(j);
    return MarketItemForAuthor(
      id: base.id,
      name: base.name,
      description: base.description,
      iconUrl: base.iconUrl,
      tags: base.tags,
      nodesCount: base.nodesCount,
      getsCount: base.getsCount,
      activeSessions: base.activeSessions,
      ratingAvg: base.ratingAvg,
      ratingCount: base.ratingCount,
      createdAt: base.createdAt,
      author: base.author,
      teleOpenBadge: base.teleOpenBadge,
      contactUrl: base.contactUrl,
      groupKind: base.groupKind,
      recentReviews: ((j['recent_reviews'] as List?) ?? [])
          .map((e) => MarketReview.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// Бейджи TeleOpen — специальные метки модератора
enum TeleOpenBadge {
  partner, // Партнеры TeleOpen
  verified, // Верифицировано TeleOpen
  official, // От TeleOpen
}

extension TeleOpenBadgeExt on TeleOpenBadge {
  String get label {
    switch (this) {
      case TeleOpenBadge.partner:
        return 'Партнеры TeleOpen';
      case TeleOpenBadge.verified:
        return 'Верифицировано TeleOpen';
      case TeleOpenBadge.official:
        return 'От TeleOpen';
    }
  }

  String get apiValue {
    switch (this) {
      case TeleOpenBadge.partner:
        return 'partner';
      case TeleOpenBadge.verified:
        return 'verified';
      case TeleOpenBadge.official:
        return 'official';
    }
  }

  static TeleOpenBadge? fromApi(String? value) {
    switch (value) {
      case 'partner':
        return TeleOpenBadge.partner;
      case 'verified':
        return TeleOpenBadge.verified;
      case 'official':
        return TeleOpenBadge.official;
      default:
        return null;
    }
  }
}

/// Список допустимых тегов (синхронизирован с бэком)
const kMarketValidTags = [
  'Free',
  'From GitHub',
  'Discord',
  'Telegram',
  'WhatsApp',
  'Signal',
  'Facebook',
  'Instagram',
  'Threads',
  'X',
  'Linkedln',
  'Clubhouse',
  'TikTok',
  'Twitch',
  'YouTube',
  'Netflix',
  'Spotify',
  'SoundCloud',
  'Deezer',
  'Patreon',
  'Substack',
  'ChatGPT',
  'Gemini',
  'Claude',
  'Midjourney',
  'Copilot',
  'For Gaming',
  'Brawl Stars',
  'Clash Of Clans',
  'Clash Royal',
  'Roblox',
  'PH',
  'OF',
];

/// Элемент маркетплейса для модераторской панели (содержит nodes и author_telegram_id)
class AdminMarketItem extends MarketItem {
  final int authorTelegramId;
  final bool authorPublishBanned;
  final List<Map<String, dynamic>> nodes;

  AdminMarketItem({
    required super.id,
    required super.name,
    required super.description,
    required super.iconUrl,
    required super.tags,
    required super.nodesCount,
    required super.getsCount,
    required super.activeSessions,
    required super.ratingAvg,
    required super.ratingCount,
    required super.createdAt,
    required super.author,
    super.teleOpenBadge,
    super.contactUrl,
    super.groupKind,
    required this.authorTelegramId,
    required this.authorPublishBanned,
    required this.nodes,
  });

  factory AdminMarketItem.fromJson(Map<String, dynamic> j) {
    final base = MarketItem.fromJson(j);
    return AdminMarketItem(
      id: base.id,
      name: base.name,
      description: base.description,
      iconUrl: base.iconUrl,
      tags: base.tags,
      nodesCount: base.nodesCount,
      getsCount: base.getsCount,
      activeSessions: base.activeSessions,
      ratingAvg: base.ratingAvg,
      ratingCount: base.ratingCount,
      createdAt: base.createdAt,
      author: base.author,
      teleOpenBadge: base.teleOpenBadge,
      contactUrl: base.contactUrl,
      groupKind: base.groupKind,
      authorTelegramId: (j['author_telegram_id'] as num?)?.toInt() ?? 0,
      authorPublishBanned: j['author_publish_banned'] == true,
      nodes: ((j['nodes'] as List?) ?? [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList(),
    );
  }
}

/// Дашборд автора: накопительная статистика по своей публикации.
class AuthorStats {
  final int groupId;
  final int uniqueUsers; // уникальные Telegram-аккаунты, добавившие подписку
  final int uniqueDevices; // уникальные устройства, реально гонявшие трафик
  final int activeDevices24h; // устройства, активные за сутки
  final int activeUsers15m; // активны прямо сейчас (окно 15 мин)
  final int totalUpload; // байт всего выгружено
  final int totalDownload; // байт всего скачано
  final int totalTraffic; // upload + download
  final int topDeviceTraffic; // максимум трафика на одном устройстве
  final int totalSeconds; // суммарное время использования
  final double totalHours; // то же в часах
  final int getsCount; // сколько раз подписку «забирали»
  final int activeSessions; // счётчик сессий
  final int nodesCount;
  final double ratingAvg;
  final int ratingCount;

  AuthorStats({
    required this.groupId,
    required this.uniqueUsers,
    required this.uniqueDevices,
    required this.activeDevices24h,
    required this.activeUsers15m,
    required this.totalUpload,
    required this.totalDownload,
    required this.totalTraffic,
    required this.topDeviceTraffic,
    required this.totalSeconds,
    required this.totalHours,
    required this.getsCount,
    required this.activeSessions,
    required this.nodesCount,
    required this.ratingAvg,
    required this.ratingCount,
  });

  factory AuthorStats.fromJson(Map<String, dynamic> j) {
    int i(String k) => (j[k] as num?)?.toInt() ?? 0;
    double d(String k) => (j[k] as num?)?.toDouble() ?? 0.0;
    return AuthorStats(
      groupId: i('group_id'),
      uniqueUsers: i('unique_users'),
      uniqueDevices: i('unique_devices'),
      activeDevices24h: i('active_devices_24h'),
      activeUsers15m: i('active_users_15m'),
      totalUpload: i('total_upload'),
      totalDownload: i('total_download'),
      totalTraffic: i('total_traffic'),
      topDeviceTraffic: i('top_device_traffic'),
      totalSeconds: i('total_seconds'),
      totalHours: d('total_hours'),
      getsCount: i('gets_count'),
      activeSessions: i('active_sessions'),
      nodesCount: i('nodes_count'),
      ratingAvg: d('rating_avg'),
      ratingCount: i('rating_count'),
    );
  }
}

// ─── Платный маркет ──────────────────────────────────────────────────────────

/// Покупка платной подписки (право доступа покупателя).
class MarketPurchase {
  final String id;
  final int? groupId;
  final String status; // pending | active | canceled
  final DateTime? expiresAt;
  final int? trafficTotal; // байт, null = безлимит
  final int trafficUsed;
  final int? deviceLimit;
  final int devices; // куплено устройств (1 = только базовое)
  final int durationDays;
  final double priceRub;
  final String? accessCode;
  final String? subUrl;

  // Только в /market/my_purchases:
  final String groupName;
  final String iconUrl;
  final double? currentPriceRub;

  MarketPurchase({
    required this.id,
    required this.groupId,
    required this.status,
    required this.expiresAt,
    required this.trafficTotal,
    required this.trafficUsed,
    required this.deviceLimit,
    this.devices = 1,
    required this.durationDays,
    required this.priceRub,
    required this.accessCode,
    required this.subUrl,
    this.groupName = '',
    this.iconUrl = '',
    this.currentPriceRub,
  });

  bool get isActive =>
      status == 'active' &&
      (expiresAt == null || expiresAt!.isAfter(DateTime.now())) &&
      (trafficTotal == null || trafficUsed < trafficTotal!);

  /// Сколько дней осталось (0 — истекла/нет срока).
  int get daysLeft {
    if (expiresAt == null) return 0;
    final d = expiresAt!.difference(DateTime.now()).inDays;
    return d < 0 ? 0 : d;
  }

  factory MarketPurchase.fromJson(Map<String, dynamic> j) => MarketPurchase(
        id: j['id']?.toString() ?? '',
        groupId: (j['group_id'] as num?)?.toInt(),
        status: j['status'] ?? 'pending',
        expiresAt: j['expires_at'] == null
            ? null
            : DateTime.tryParse(j['expires_at'].toString()),
        trafficTotal: (j['traffic_total'] as num?)?.toInt(),
        trafficUsed: (j['traffic_used'] as num?)?.toInt() ?? 0,
        deviceLimit: (j['device_limit'] as num?)?.toInt(),
        devices: (j['devices'] as num?)?.toInt() ?? 1,
        durationDays: (j['duration_days'] as num?)?.toInt() ?? 0,
        priceRub: (j['price_rub'] as num?)?.toDouble() ?? 0,
        accessCode: j['access_code'] as String?,
        subUrl: j['sub_url'] as String?,
        groupName: j['group_name'] ?? '',
        iconUrl: j['icon_url'] ?? '',
        currentPriceRub: (j['current_price_rub'] as num?)?.toDouble(),
      );
}

/// Результат POST /market/buy — ссылка на оплату по СБП либо (при оплате
/// балансом) сразу проведённая покупка.
class MarketBuyResult {
  final String paymentId;
  final String purchaseId;
  final String url;
  final double amountRub;
  final bool paidWithBalance;
  final double? balanceRub; // остаток после оплаты балансом
  final MarketPurchase? purchase; // сразу активная покупка (balance)

  MarketBuyResult({
    required this.paymentId,
    required this.purchaseId,
    required this.url,
    required this.amountRub,
    this.paidWithBalance = false,
    this.balanceRub,
    this.purchase,
  });

  factory MarketBuyResult.fromJson(Map<String, dynamic> j) => MarketBuyResult(
        paymentId: j['payment_id'] ?? '',
        purchaseId: j['purchase_id'] ?? '',
        url: j['url'] ?? '',
        amountRub: (j['amount_rub'] as num?)?.toDouble() ?? 0,
        paidWithBalance: j['paid_with_balance'] == true,
        balanceRub: (j['balance_rub'] as num?)?.toDouble(),
        purchase: j['purchase'] == null
            ? null
            : MarketPurchase.fromJson(
                (j['purchase'] as Map).cast<String, dynamic>()),
      );
}

/// Заявка на вывод средств продавца.
class SellerPayout {
  final int id;
  final double amountRub;
  final String details;
  final String status; // pending | paid | rejected
  final DateTime createdAt;

  SellerPayout({
    required this.id,
    required this.amountRub,
    required this.details,
    required this.status,
    required this.createdAt,
  });

  factory SellerPayout.fromJson(Map<String, dynamic> j) => SellerPayout(
        id: (j['id'] as num).toInt(),
        amountRub: (j['amount_rub'] as num?)?.toDouble() ?? 0,
        details: j['details'] ?? '',
        status: j['status'] ?? 'pending',
        createdAt: DateTime.tryParse(j['created_at'] ?? '') ?? DateTime.now(),
      );
}

/// Продажа в истории продавца (сумма — уже доля продавца, за вычетом комиссии).
class SellerSale {
  final double amountRub;
  final String kind; // purchase | renewal
  final String groupName;
  final DateTime? at;

  SellerSale({
    required this.amountRub,
    required this.kind,
    required this.groupName,
    required this.at,
  });

  factory SellerSale.fromJson(Map<String, dynamic> j) => SellerSale(
        amountRub: (j['amount_rub'] as num?)?.toDouble() ?? 0,
        kind: j['kind'] ?? 'purchase',
        groupName: j['group_name'] ?? '',
        at: j['at'] == null ? null : DateTime.tryParse(j['at'].toString()),
      );
}

/// Кабинет продавца: статус ключа, баланс, история.
class SellerInfo {
  final bool isSeller;
  final String? keyMasked;
  final double feePct;
  final double balanceRub;
  final double totalEarnedRub;
  final int salesCount;
  final List<SellerPayout> payouts;
  final List<SellerSale> sales;

  SellerInfo({
    required this.isSeller,
    required this.keyMasked,
    required this.feePct,
    required this.balanceRub,
    required this.totalEarnedRub,
    required this.salesCount,
    required this.payouts,
    required this.sales,
  });

  factory SellerInfo.fromJson(Map<String, dynamic> j) => SellerInfo(
        isSeller: j['is_seller'] == true,
        keyMasked: j['key_masked'] as String?,
        feePct: (j['fee_pct'] as num?)?.toDouble() ?? 0,
        balanceRub: (j['balance_rub'] as num?)?.toDouble() ?? 0,
        totalEarnedRub: (j['total_earned_rub'] as num?)?.toDouble() ?? 0,
        salesCount: (j['sales_count'] as num?)?.toInt() ?? 0,
        payouts: ((j['payouts'] as List?) ?? [])
            .map((e) =>
                SellerPayout.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        sales: ((j['sales'] as List?) ?? [])
            .map((e) => SellerSale.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

/// Панель/сервер продавца для выдачи персональных UUID (защита платных подписок).
class SellerPanel {
  final int id;
  final String kind; // panel-3xui | panel-marzban | xray-local
  final String label;
  final String endpoint;
  final String inbound;
  final String host;
  final bool enabled;
  final int groupsCount;

  SellerPanel({
    required this.id,
    required this.kind,
    required this.label,
    required this.endpoint,
    required this.inbound,
    required this.host,
    required this.enabled,
    required this.groupsCount,
  });

  factory SellerPanel.fromJson(Map<String, dynamic> j) => SellerPanel(
        id: (j['id'] as num).toInt(),
        kind: (j['kind'] as String?) ?? '',
        label: (j['label'] as String?) ?? '',
        endpoint: (j['endpoint'] as String?) ?? '',
        inbound: j['inbound']?.toString() ?? '',
        host: (j['host'] as String?) ?? '',
        enabled: j['enabled'] == true,
        groupsCount: (j['groups_count'] as num?)?.toInt() ?? 0,
      );

  String get kindLabel => switch (kind) {
        'panel-3xui' => '3x-ui',
        'panel-marzban' => 'Marzban',
        'xray-local' => 'xray (этот сервер)',
        _ => kind,
      };
}

/// Один inbound панели при подключении (нужен выбор, если их несколько).
class PanelInbound {
  final Object? id;
  final String tag;
  final String protocol;
  final String remark;
  final int? port;
  final bool active; // активный инбаунд панели (meta.inbound_id)

  PanelInbound(
      {this.id,
      required this.tag,
      required this.protocol,
      required this.remark,
      this.port,
      this.active = false});

  factory PanelInbound.fromJson(Map<String, dynamic> j) => PanelInbound(
        id: j['id'],
        tag: (j['tag'] as String?) ?? '',
        protocol: (j['protocol'] as String?) ?? '',
        remark: (j['remark'] as String?) ?? '',
        port: (j['port'] as num?)?.toInt(),
        active: j['active'] == true,
      );

  String get label {
    final r = remark.isNotEmpty ? remark : (tag.isNotEmpty ? tag : '#$id');
    return port != null ? '$r · :$port · $protocol' : '$r · $protocol';
  }
}

/// Seller-ключ в админке.
class AdminSellerKey {
  final int id;
  final String key;
  final String note;
  final bool revoked;
  final int? telegramId;
  final String username;
  final String firstName;
  final DateTime createdAt;
  final DateTime? activatedAt;

  AdminSellerKey({
    required this.id,
    required this.key,
    required this.note,
    required this.revoked,
    required this.telegramId,
    required this.username,
    required this.firstName,
    required this.createdAt,
    required this.activatedAt,
  });

  factory AdminSellerKey.fromJson(Map<String, dynamic> j) => AdminSellerKey(
        id: (j['id'] as num).toInt(),
        key: j['key'] ?? '',
        note: j['note'] ?? '',
        revoked: j['revoked'] == true,
        telegramId: (j['telegram_id'] as num?)?.toInt(),
        username: j['username'] ?? '',
        firstName: j['first_name'] ?? '',
        createdAt: DateTime.tryParse(j['created_at'] ?? '') ?? DateTime.now(),
        activatedAt: j['activated_at'] == null
            ? null
            : DateTime.tryParse(j['activated_at'].toString()),
      );
}

/// Заявка на вывод в админке (с инфо о продавце).
class AdminSellerPayout extends SellerPayout {
  final int sellerId;
  final String username;
  final String firstName;

  AdminSellerPayout({
    required super.id,
    required super.amountRub,
    required super.details,
    required super.status,
    required super.createdAt,
    required this.sellerId,
    required this.username,
    required this.firstName,
  });

  factory AdminSellerPayout.fromJson(Map<String, dynamic> j) {
    final base = SellerPayout.fromJson(j);
    return AdminSellerPayout(
      id: base.id,
      amountRub: base.amountRub,
      details: base.details,
      status: base.status,
      createdAt: base.createdAt,
      sellerId: (j['seller_id'] as num?)?.toInt() ?? 0,
      username: j['username'] ?? '',
      firstName: j['first_name'] ?? '',
    );
  }
}

/// Запись баланса юзера в админке.
class UserBalanceEntry {
  final int telegramId;
  final String username;
  final String firstName;
  final double balanceRub;
  final DateTime? updatedAt;

  UserBalanceEntry({
    required this.telegramId,
    required this.username,
    required this.firstName,
    required this.balanceRub,
    required this.updatedAt,
  });

  factory UserBalanceEntry.fromJson(Map<String, dynamic> j) => UserBalanceEntry(
        telegramId: (j['telegram_id'] as num?)?.toInt() ?? 0,
        username: j['username'] ?? '',
        firstName: j['first_name'] ?? '',
        balanceRub: (j['balance_rub'] as num?)?.toDouble() ?? 0,
        updatedAt: j['updated_at'] == null
            ? null
            : DateTime.tryParse(j['updated_at'].toString()),
      );
}

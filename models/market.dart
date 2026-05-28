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
        author: MarketAuthor.fromJson((j['author'] as Map).cast<String, dynamic>()),
      );
}

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

  
  final String groupKind;

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
    this.groupKind = 'vpn',
  });

  
  bool get isMtProto => groupKind == 'mtproto';

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
        author: MarketAuthor.fromJson((j['author'] as Map).cast<String, dynamic>()),
        teleOpenBadge: TeleOpenBadgeExt.fromApi(j['teleopen_badge'] as String?),
        groupKind: (j['group_kind'] as String?) ?? 'vpn',
      );
}

class MarketDetail extends MarketItem {
  final List<MarketReview> reviews;
  final MarketReview? myReview;
  final SpeedStats speed15m;

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
    super.groupKind,
    required this.reviews,
    required this.myReview,
    required this.speed15m,
  });

  factory MarketDetail.fromJson(Map<String, dynamic> j) {
    final base = MarketItem.fromJson(j);
    final my = j['my_review'];
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
      groupKind: base.groupKind,
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
    );
  }
}

class SpeedStats {
  final int uploadBytes;
  final int downloadBytes;
  final int activeUsers;

  SpeedStats({this.uploadBytes = 0, this.downloadBytes = 0, this.activeUsers = 0});

  factory SpeedStats.fromJson(Map<String, dynamic> j) => SpeedStats(
        uploadBytes: (j['upload_bytes'] as num?)?.toInt() ?? 0,
        downloadBytes: (j['download_bytes'] as num?)?.toInt() ?? 0,
        activeUsers: (j['active_users'] as num?)?.toInt() ?? 0,
      );
}

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

class NodeHealth {
  final String uriHash;
  final int reports;
  final bool broken;

  NodeHealth({required this.uriHash, required this.reports, required this.broken});

  factory NodeHealth.fromJson(Map<String, dynamic> j) => NodeHealth(
        uriHash: j['uri_hash'] ?? '',
        reports: (j['reports'] as num?)?.toInt() ?? 0,
        broken: j['broken'] == true,
      );
}

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
      groupKind: base.groupKind,
      recentReviews: ((j['recent_reviews'] as List?) ?? [])
          .map((e) => MarketReview.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

enum TeleOpenBadge {
  partner,    
  verified,   
  official,   
}

extension TeleOpenBadgeExt on TeleOpenBadge {
  String get label {
    switch (this) {
      case TeleOpenBadge.partner:  return 'Партнеры TeleOpen';
      case TeleOpenBadge.verified: return 'Верифицировано TeleOpen';
      case TeleOpenBadge.official: return 'От TeleOpen';
    }
  }

  String get apiValue {
    switch (this) {
      case TeleOpenBadge.partner:  return 'partner';
      case TeleOpenBadge.verified: return 'verified';
      case TeleOpenBadge.official: return 'official';
    }
  }

  static TeleOpenBadge? fromApi(String? value) {
    switch (value) {
      case 'partner':  return TeleOpenBadge.partner;
      case 'verified': return TeleOpenBadge.verified;
      case 'official': return TeleOpenBadge.official;
      default: return null;
    }
  }
}

const kMarketValidTags = [
  'Free', 'From GitHub',
  'Discord', 'Telegram', 'WhatsApp', 'Signal',
  'Facebook', 'Instagram', 'Threads', 'X', 'Linkedln', 'Clubhouse',
  'TikTok', 'Twitch', 'YouTube',
  'Netflix', 'Spotify', 'SoundCloud', 'Deezer',
  'Patreon', 'Substack',
  'ChatGPT', 'Gemini', 'Claude', 'Midjourney', 'Copilot',
  'For Gaming', 'Brawl Stars', 'Clash Of Clans', 'Clash Royal', 'Roblox',
  'PH', 'OF',
];

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
      groupKind: base.groupKind,
      authorTelegramId: (j['author_telegram_id'] as num?)?.toInt() ?? 0,
      authorPublishBanned: j['author_publish_banned'] == true,
      nodes: ((j['nodes'] as List?) ?? [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList(),
    );
  }
}

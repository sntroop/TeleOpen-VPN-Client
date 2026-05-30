// lib/logic/market_api.dart
//
// HTTP-клиент маркетплейса.
// 1-в-1 с FastAPI бэкендом (kApiBase).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../models/market.dart';
import '../models/theme.dart';

const String kApiBase = 'https://teleopen.space';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => 'API[$status]: $message';
}

class MarketApi {
  static const Duration _timeout = Duration(seconds: 12);

  /// JWT-токен. Устанавливается после логина, загружается из prefs.
  static String? _jwt;

  static void setJwt(String? token) => _jwt = token;
  static String? get jwt => _jwt;

  /// Заголовки с авторизацией.
  static Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (_jwt != null) 'Authorization': 'Bearer $_jwt',
      };

  static Map<String, String> get _authHeadersNoBody => {
        if (_jwt != null) 'Authorization': 'Bearer $_jwt',
      };

  // ─── Auth flow ───────────────────────────────────────────────────────────

  /// Запросить токен авторизации. Возвращает строку токена.
  static Future<String> authInit() async {
    final r = await http.post(Uri.parse('$kApiBase/auth/init')).timeout(_timeout);
    _check(r);
    return (jsonDecode(r.body) as Map)['token'] as String;
  }

  /// Опрос токена. Возвращает `null` пока ожидание, ({TgUser user, String jwt}) при готовности.
  static Future<({TgUser user, String jwt})?> authPoll(String token) async {
    final r = await http.get(Uri.parse('$kApiBase/auth/poll/$token')).timeout(_timeout);
    _check(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    if (body['status'] == 'pending') return null;
    final user = TgUser.fromJson((body['user'] as Map).cast<String, dynamic>());
    final jwt = body['jwt'] as String? ?? '';
    return (user: user, jwt: jwt);
  }

  // ─── Market list / detail ────────────────────────────────────────────────

  static Future<({List<MarketItem> items, int total})> list({
    int offset = 0,
    int limit = 20,
    String search = '',
    List<String> tags = const [],
  }) async {
    final qp = <String, String>{
      'offset': '$offset',
      'limit': '$limit',
      if (search.isNotEmpty) 'search': search,
      if (tags.isNotEmpty) 'tags': tags.join(','),
    };
    final r = await http
        .get(Uri.parse('$kApiBase/market/list').replace(queryParameters: qp),
            headers: _authHeadersNoBody)
        .timeout(_timeout);
    _check(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final items = ((body['items'] as List?) ?? [])
        .map((e) => MarketItem.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return (items: items, total: (body['total'] as num?)?.toInt() ?? items.length);
  }

  static Future<MarketDetail> detail(int groupId, {int? userId}) async {
    final qp = <String, String>{if (userId != null) 'user_id': '$userId'};
    final r = await http
        .get(Uri.parse('$kApiBase/market/detail/$groupId').replace(queryParameters: qp))
        .timeout(_timeout);
    _check(r);
    return MarketDetail.fromJson((jsonDecode(r.body) as Map).cast<String, dynamic>());
  }

  /// Получить серверы (URI) подписки. Параллельно сервер инкрементит gets_count.
  static Future<({String name, List<MarketNode> nodes})> get(int groupId) async {
    final r = await http.get(Uri.parse('$kApiBase/market/get/$groupId')).timeout(_timeout);
    _check(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final nodes = ((body['nodes'] as List?) ?? [])
        .map((e) => MarketNode.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return (name: (body['name'] as String?) ?? '', nodes: nodes);
  }

  // ─── Отзывы ─────────────────────────────────────────────────────────────

  static Future<void> postReview({
    required int groupId,
    required int rating,
    required String comment,
  }) async {
    final r = await http
        .post(
          Uri.parse('$kApiBase/market/review'),
          headers: _authHeaders,
          body: jsonEncode({
            'group_id': groupId,
            'rating': rating,
            'comment': comment,
          }),
        )
        .timeout(_timeout);
    _check(r);
  }

  // ─── Сессии / отчёты ────────────────────────────────────────────────────

  static Future<void> startSession({required int groupId}) async {
    final r = await http
        .post(
          Uri.parse('$kApiBase/market/session'),
          headers: _authHeaders,
          body: jsonEncode({'group_id': groupId}),
        )
        .timeout(_timeout);
    _check(r);
  }

  static Future<void> reportNode({
    required int groupId,
    required String nodeUriHash,
  }) async {
    final r = await http
        .post(
          Uri.parse('$kApiBase/market/report_node'),
          headers: _authHeaders,
          body: jsonEncode({
            'group_id': groupId,
            'node_uri_hash': nodeUriHash,
          }),
        )
        .timeout(_timeout);
    _check(r);
  }

  static Future<List<NodeHealth>> nodeHealth(int groupId) async {
    final r = await http.get(Uri.parse('$kApiBase/market/node_health/$groupId')).timeout(_timeout);
    _check(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    return ((body['nodes'] as List?) ?? [])
        .map((e) => NodeHealth.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  static Future<void> speedReport({
    required int groupId,
    required int uploadBytes,
    required int downloadBytes,
  }) async {
    final r = await http
        .post(
          Uri.parse('$kApiBase/market/speed_report'),
          headers: _authHeaders,
          body: jsonEncode({
            'group_id': groupId,
            'upload_bytes': uploadBytes,
            'download_bytes': downloadBytes,
          }),
        )
        .timeout(_timeout);
    _check(r);
  }

  static Future<LiveStats> liveStats(int groupId) async {
    final r = await http.get(Uri.parse('$kApiBase/market/live_stats/$groupId')).timeout(_timeout);
    _check(r);
    return LiveStats.fromJson((jsonDecode(r.body) as Map).cast<String, dynamic>());
  }

  // ─── Author / publish ───────────────────────────────────────────────────

  static Future<List<MarketItemForAuthor>> authorPanel(int telegramId) async {
    final r = await http.get(Uri.parse('$kApiBase/market/author/$telegramId')).timeout(_timeout);
    _check(r);
    final list = jsonDecode(r.body) as List;
    return list.map((e) => MarketItemForAuthor.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  /// Опубликовать набор серверов. Возвращает id новой группы.
  static Future<int> publish({
    required String name,
    required String description,
    required String iconUrl,
    required List<String> tags,
    required List<Map<String, dynamic>> nodes,
    String kind = 'vpn',
  }) async {
    final r = await http
        .post(
          Uri.parse('$kApiBase/market/publish'),
          headers: _authHeaders,
          body: jsonEncode({
            'name': name,
            'description': description,
            'icon_url': iconUrl,
            'tags': tags,
            'nodes': nodes,
            'kind': kind,
          }),
        )
        .timeout(_timeout);
    _check(r);
    return ((jsonDecode(r.body) as Map)['id'] as num).toInt();
  }

  static Future<void> deleteGroup({required int groupId}) async {
    final req = http.Request('DELETE', Uri.parse('$kApiBase/market/delete/$groupId'));
    req.headers.addAll(_authHeaders);
    final streamed = await req.send().timeout(_timeout);
    final r = await http.Response.fromStream(streamed);
    _check(r);
  }

  // ─── Admin / moderation ─────────────────────────────────────────────────

  /// Список всех подписок для модератора (с нодами и инфо об авторе).
  static Future<({List<AdminMarketItem> items, int total})> adminList({
    int offset = 0,
    int limit = 50,
  }) async {
    final qp = {'offset': '$offset', 'limit': '$limit'};
    final r = await http
        .get(Uri.parse('$kApiBase/admin/market/list').replace(queryParameters: qp),
            headers: _authHeadersNoBody)
        .timeout(_timeout);
    _check(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final items = ((body['items'] as List?) ?? [])
        .map((e) => AdminMarketItem.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return (items: items, total: (body['total'] as num?)?.toInt() ?? items.length);
  }

  /// Удалить любую подписку (только модератор).
  static Future<void> adminDeleteGroup({required int groupId}) async {
    final req = http.Request('DELETE', Uri.parse('$kApiBase/admin/market/delete/$groupId'));
    req.headers.addAll(_authHeaders);
    final streamed = await req.send().timeout(_timeout);
    final r = await http.Response.fromStream(streamed);
    _check(r);
  }

  /// Забанить или разбанить пользователя (запрет публикации).
  static Future<void> adminSetBan({
    required int targetTelegramId,
    required bool banned,
  }) async {
    final r = await http
        .post(
          Uri.parse('$kApiBase/admin/user/ban'),
          headers: _authHeaders,
          body: jsonEncode({
            'target_telegram_id': targetTelegramId,
            'banned': banned,
          }),
        )
        .timeout(_timeout);
    _check(r);
  }

  /// Редактировать подписку (только модератор).
  /// Передавай только те поля, которые нужно изменить.
  static Future<void> adminEditGroup({
    required int groupId,
    String? name,
    String? description,
    String? iconUrl,
    List<String>? tags,
    List<Map<String, dynamic>>? nodes,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (iconUrl != null) body['icon_url'] = iconUrl;
    if (tags != null) body['tags'] = tags;
    if (nodes != null) body['nodes'] = nodes;

    final req = http.Request('PATCH', Uri.parse('$kApiBase/admin/market/edit/$groupId'));
    req.headers.addAll(_authHeaders);
    req.body = jsonEncode(body);
    final streamed = await req.send().timeout(_timeout);
    final r = await http.Response.fromStream(streamed);
    _check(r);
  }

  /// Установить или снять TeleOpen-бейдж на подписке (только модератор).
  /// [badge] — 'partner' | 'verified' | 'official' | null (снять бейдж).
  static Future<void> adminSetBadge({
    required int groupId,
    required String? badge,
  }) async {
    final req = http.Request('PATCH', Uri.parse('$kApiBase/admin/market/badge/$groupId'));
    req.headers.addAll(_authHeaders);
    req.body = jsonEncode({'teleopen_badge': badge});
    final streamed = await req.send().timeout(_timeout);
    final r = await http.Response.fromStream(streamed);
    _check(r);
  }

  // ─── Upload icon ────────────────────────────────────────────────────────

  static Future<String> uploadIcon(File file) async {
    final req = http.MultipartRequest('POST', Uri.parse('$kApiBase/upload/icon'));
    if (_jwt != null) req.headers['Authorization'] = 'Bearer $_jwt';
    req.files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await req.send().timeout(const Duration(seconds: 30));
    final r = await http.Response.fromStream(streamed);
    _check(r);
    return (jsonDecode(r.body) as Map)['url'] as String;
  }

  // ─── Themes ─────────────────────────────────────────────────────────────

  static Future<({List<UserTheme> items, int total})> themesList({
    int offset = 0,
    int limit = 30,
    String sort = 'popular', // 'popular' | 'new'
    String? mode,             // 'light' | 'dark'
  }) async {
    final qp = {'offset': '$offset', 'limit': '$limit', 'sort': sort};
    if (mode != null) qp['mode'] = mode;
    final r = await http
        .get(Uri.parse('$kApiBase/themes/list').replace(queryParameters: qp))
        .timeout(_timeout);
    _check(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final items = (body['items'] as List)
        .map((e) => UserTheme.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return (items: items, total: (body['total'] as num).toInt());
  }

  static Future<UserTheme> themeGet(int themeId) async {
    final r = await http.get(Uri.parse('$kApiBase/themes/$themeId')).timeout(_timeout);
    _check(r);
    return UserTheme.fromJson(
        (jsonDecode(r.body) as Map).cast<String, dynamic>());
  }

  /// Возвращает id опубликованной темы.
  static Future<int> themePublish({
    int? themeId,
    required UserTheme theme,
  }) async {
    final body = <String, dynamic>{
      if (themeId != null) 'theme_id': themeId,
      'name': theme.name,
      'mode': theme.mode,
      'colors': theme.colors.toJson(),
      'radii': theme.radii.toJson(),
      'background': theme.background.toJson(),
    };
    final r = await http
        .post(Uri.parse('$kApiBase/themes/publish'),
            headers: _authHeaders,
            body: jsonEncode(body))
        .timeout(_timeout);
    _check(r);
    return ((jsonDecode(r.body) as Map)['id'] as num).toInt();
  }

  static Future<void> themeInstall(int themeId) async {
    final r = await http
        .post(Uri.parse('$kApiBase/themes/$themeId/install'))
        .timeout(_timeout);
    _check(r);
  }

  static Future<void> themeDelete({required int themeId}) async {
    final req = http.Request('DELETE', Uri.parse('$kApiBase/themes/$themeId'));
    req.headers.addAll(_authHeaders);
    final streamed = await req.send().timeout(_timeout);
    final r = await http.Response.fromStream(streamed);
    _check(r);
  }

  // ─── Internals ──────────────────────────────────────────────────────────

  static void _check(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    String msg;
    try {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      msg = j['detail']?.toString() ?? r.body;
    } catch (_) {
      msg = r.body;
    }
    throw ApiException(r.statusCode, msg);
  }
}

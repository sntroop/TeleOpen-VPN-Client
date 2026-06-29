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
import '../models/announcement.dart';

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
  static Future<({String name, String iconUrl, String contactUrl, List<MarketNode> nodes})> get(int groupId) async {
    final r = await http
        .get(Uri.parse('$kApiBase/market/get/$groupId'), headers: _authHeadersNoBody)
        .timeout(_timeout);
    _check(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final nodes = ((body['nodes'] as List?) ?? [])
        .map((e) => MarketNode.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return (
      name: (body['name'] as String?) ?? '',
      iconUrl: (body['icon_url'] as String?) ?? '',
      contactUrl: (body['contact_url'] as String?) ?? '',
      nodes: nodes,
    );
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

  /// Жалоба на подписку целиком (спам/мошенничество/нерабочая).
  static Future<void> reportGroup({
    required int groupId,
    String reason = '',
  }) async {
    final r = await http
        .post(
          Uri.parse('$kApiBase/market/report_group'),
          headers: _authHeaders,
          body: jsonEncode({
            'group_id': groupId,
            'reason': reason,
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
    String contactUrl = '',
    String kind = 'vpn',
    bool isPaid = false,
    List<MarketTariff>? tariffs,
    int? paidTrafficGb,
    int? paidDeviceLimit,
    double? extraDevicePriceRub,
    double? extraGbPriceRub,
    int? panelId,
  }) async {
    final r = await http
        .post(
          Uri.parse('$kApiBase/market/publish'),
          headers: _authHeaders,
          body: jsonEncode({
            'name': name,
            'description': description,
            'icon_url': iconUrl,
            'contact_url': contactUrl,
            'tags': tags,
            'nodes': nodes,
            'kind': kind,
            'is_paid': isPaid,
            if (isPaid) 'tariffs': (tariffs ?? []).map((t) => t.toJson()).toList(),
            if (isPaid) 'paid_traffic_gb': paidTrafficGb ?? 0,
            if (isPaid) 'paid_device_limit': paidDeviceLimit ?? 0,
            if (isPaid) 'extra_device_price_rub': extraDevicePriceRub ?? 0,
            if (isPaid) 'extra_gb_price_rub': extraGbPriceRub ?? 0,
            if (isPaid && panelId != null) 'panel_id': panelId,
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

  /// Полные данные СВОЕЙ публикации для редактирования (URI серверов + displayName).
  static Future<({String name, String description, String iconUrl, String contactUrl, List<String> tags, List<Map<String, dynamic>> nodes, bool isPaid, List<MarketTariff> tariffs, int? paidTrafficGb, int? paidDeviceLimit, double? extraDevicePriceRub, double? extraGbPriceRub, int? panelId})>
      mineGroup(int groupId) async {
    final r = await http
        .get(Uri.parse('$kApiBase/market/mine/$groupId'), headers: _authHeadersNoBody)
        .timeout(_timeout);
    _check(r);
    final b = jsonDecode(r.body) as Map<String, dynamic>;
    return (
      name: (b['name'] as String?) ?? '',
      description: (b['description'] as String?) ?? '',
      iconUrl: (b['icon_url'] as String?) ?? '',
      contactUrl: (b['contact_url'] as String?) ?? '',
      tags: ((b['tags'] as List?) ?? []).map((e) => e.toString()).toList(),
      nodes: ((b['nodes'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      isPaid: b['is_paid'] == true,
      tariffs: ((b['tariffs'] as List?) ?? [])
          .map((e) => MarketTariff.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      paidTrafficGb: (b['paid_traffic_gb'] as num?)?.toInt(),
      paidDeviceLimit: (b['paid_device_limit'] as num?)?.toInt(),
      extraDevicePriceRub: (b['extra_device_price_rub'] as num?)?.toDouble(),
      extraGbPriceRub: (b['extra_gb_price_rub'] as num?)?.toDouble(),
      panelId: (b['panel_id'] as num?)?.toInt(),
    );
  }

  /// Редактировать СВОЮ публикацию (автор). Передавай только изменённые поля.
  /// [isPaid] != null включает обновление всего платного блока разом.
  static Future<void> editGroup({
    required int groupId,
    String? name,
    String? description,
    String? iconUrl,
    String? contactUrl,
    List<String>? tags,
    List<Map<String, dynamic>>? nodes,
    bool? isPaid,
    List<MarketTariff>? tariffs,
    int? paidTrafficGb,
    int? paidDeviceLimit,
    double? extraDevicePriceRub,
    double? extraGbPriceRub,
    int? panelId,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (iconUrl != null) body['icon_url'] = iconUrl;
    if (contactUrl != null) body['contact_url'] = contactUrl;
    if (tags != null) body['tags'] = tags;
    if (nodes != null) body['nodes'] = nodes;
    if (isPaid != null) {
      body['is_paid'] = isPaid;
      if (isPaid) {
        body['tariffs'] = (tariffs ?? []).map((t) => t.toJson()).toList();
        body['paid_traffic_gb'] = paidTrafficGb ?? 0;
        body['paid_device_limit'] = paidDeviceLimit ?? 0;
        body['extra_device_price_rub'] = extraDevicePriceRub ?? 0;
        body['extra_gb_price_rub'] = extraGbPriceRub ?? 0;
        // panel_id всегда передаём в платном блоке: число — привязать, 0 — отвязать.
        body['panel_id'] = panelId ?? 0;
      } else {
        body['panel_id'] = 0; // бесплатная — панель не нужна
      }
    }

    final req = http.Request('PATCH', Uri.parse('$kApiBase/market/edit/$groupId'));
    req.headers.addAll(_authHeaders);
    req.body = jsonEncode(body);
    final streamed = await req.send().timeout(_timeout);
    final r = await http.Response.fromStream(streamed);
    _check(r);
  }

  /// Накопительный репорт использования (дельты за завершённую сессию).
  /// Тихо глушит ошибки — это фоновая аналитика, не критичная для UX.
  static Future<void> usageReport({
    required int groupId,
    required String deviceHash,
    required int uploadDelta,
    required int downloadDelta,
    required int seconds,
  }) async {
    try {
      final r = await http
          .post(
            Uri.parse('$kApiBase/market/usage_report'),
            headers: _authHeaders,
            body: jsonEncode({
              'group_id': groupId,
              'device_hash': deviceHash,
              'upload_delta': uploadDelta,
              'download_delta': downloadDelta,
              'seconds': seconds,
            }),
          )
          .timeout(_timeout);
      _check(r);
    } catch (_) {
      // намеренно глушим
    }
  }

  /// Дашборд автора по своей публикации.
  static Future<AuthorStats> authorStats(int groupId) async {
    final r = await http
        .get(Uri.parse('$kApiBase/market/stats/$groupId'), headers: _authHeadersNoBody)
        .timeout(_timeout);
    _check(r);
    return AuthorStats.fromJson((jsonDecode(r.body) as Map).cast<String, dynamic>());
  }

  // ─── Платный маркет: покупка, продавец, админ-ключи ─────────────────────

  /// Купить (или продлить) платную подписку. Возвращает ссылку на оплату СБП.
  /// Создание платежа: покупка/продление по тарифу либо докупка.
  /// [action]: purchase|renew | extra_traffic | extra_device.
  /// [payMethod]: sbp | balance (мгновенно, без перехода в банк).
  static Future<MarketBuyResult> buyGroup(
    int groupId, {
    String action = 'purchase',
    int? tariffDays,
    int? devices,
    int? gb,
    int? count,
    String payMethod = 'sbp',
  }) async {
    final r = await http
        .post(
          Uri.parse('$kApiBase/market/buy/$groupId'),
          headers: _authHeaders,
          body: jsonEncode({
            'action': action,
            'pay_method': payMethod,
            if (tariffDays != null) 'tariff_days': tariffDays,
            if (devices != null) 'devices': devices,
            if (gb != null) 'gb': gb,
            if (count != null) 'count': count,
          }),
        )
        .timeout(const Duration(seconds: 25));
    _check(r);
    return MarketBuyResult.fromJson((jsonDecode(r.body) as Map).cast<String, dynamic>());
  }

  /// Мой внутренний баланс (выдаётся админом, тратится на покупки в маркете).
  static Future<double> myBalance() async {
    final r = await http
        .get(Uri.parse('$kApiBase/balance'), headers: _authHeadersNoBody)
        .timeout(_timeout);
    _check(r);
    return ((jsonDecode(r.body) as Map)['balance_rub'] as num?)?.toDouble() ?? 0;
  }

  /// Поллинг статуса платежа после ухода на оплату.
  /// Возвращает (статус платежа, покупка после возможной активации).
  static Future<({String paymentStatus, MarketPurchase? purchase})>
      purchaseStatus(String paymentId) async {
    final r = await http
        .get(Uri.parse('$kApiBase/market/purchase_status/$paymentId'),
            headers: _authHeadersNoBody)
        .timeout(const Duration(seconds: 25));
    _check(r);
    final b = jsonDecode(r.body) as Map<String, dynamic>;
    final p = b['purchase'];
    return (
      paymentStatus: (b['payment_status'] as String?) ?? 'pending',
      purchase: p == null
          ? null
          : MarketPurchase.fromJson((p as Map).cast<String, dynamic>()),
    );
  }

  /// Мои покупки платных подписок.
  static Future<List<MarketPurchase>> myPurchases() async {
    final r = await http
        .get(Uri.parse('$kApiBase/market/my_purchases'), headers: _authHeadersNoBody)
        .timeout(_timeout);
    _check(r);
    final b = jsonDecode(r.body) as Map<String, dynamic>;
    return ((b['purchases'] as List?) ?? [])
        .map((e) => MarketPurchase.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Дельты трафика по платной покупке (фоновое, ошибки глушим).
  static Future<void> paidUsageReport({
    required String accessCode,
    required String deviceHash,
    required int uploadDelta,
    required int downloadDelta,
    required int seconds,
  }) async {
    try {
      final r = await http
          .post(
            Uri.parse('$kApiBase/market/paid_usage'),
            headers: _authHeaders,
            body: jsonEncode({
              'access_code': accessCode,
              'device_hash': deviceHash,
              'upload_delta': uploadDelta,
              'download_delta': downloadDelta,
              'seconds': seconds,
            }),
          )
          .timeout(_timeout);
      _check(r);
    } catch (_) {
      // фоновая аналитика
    }
  }

  /// Активировать ключ продавца (TELEOPENSELLER-...).
  static Future<void> sellerActivate(String key) async {
    final r = await http
        .post(Uri.parse('$kApiBase/seller/activate'),
            headers: _authHeaders, body: jsonEncode({'key': key}))
        .timeout(_timeout);
    _check(r);
  }

  /// Кабинет продавца: статус, баланс, история продаж и выводов.
  static Future<SellerInfo> sellerMe() async {
    final r = await http
        .get(Uri.parse('$kApiBase/seller/me'), headers: _authHeadersNoBody)
        .timeout(_timeout);
    _check(r);
    return SellerInfo.fromJson((jsonDecode(r.body) as Map).cast<String, dynamic>());
  }

  /// Заявка на вывод средств (обрабатывается админом вручную).
  static Future<void> sellerPayout({
    required double amountRub,
    required String details,
  }) async {
    final r = await http
        .post(
          Uri.parse('$kApiBase/seller/payout'),
          headers: _authHeaders,
          body: jsonEncode({'amount_rub': amountRub, 'details': details}),
        )
        .timeout(_timeout);
    _check(r);
  }

  /// Список панелей продавца (для привязки к платной публикации).
  static Future<List<SellerPanel>> sellerPanels() async {
    final r = await http
        .get(Uri.parse('$kApiBase/seller/panels'), headers: _authHeadersNoBody)
        .timeout(_timeout);
    _check(r);
    final b = jsonDecode(r.body) as Map<String, dynamic>;
    return ((b['panels'] as List?) ?? [])
        .map((e) => SellerPanel.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Подключить панель. Если у удалённой панели несколько inbound и выбор не
  /// сделан — вернёт (needSelection: true, inbounds: [...], panel: null).
  /// Иначе (needSelection: false, panel: <SellerPanel>).
  static Future<({bool needSelection, List<PanelInbound> inbounds, SellerPanel? panel})>
      sellerConnectPanel(Map<String, dynamic> body) async {
    final r = await http
        .post(Uri.parse('$kApiBase/seller/panels/connect'),
            headers: _authHeaders, body: jsonEncode(body))
        .timeout(const Duration(seconds: 25));
    _check(r);
    final b = jsonDecode(r.body) as Map<String, dynamic>;
    if (b['need_selection'] == true) {
      return (
        needSelection: true,
        inbounds: ((b['inbounds'] as List?) ?? [])
            .map((e) => PanelInbound.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        panel: null,
      );
    }
    return (
      needSelection: false,
      inbounds: <PanelInbound>[],
      panel: b['panel'] != null
          ? SellerPanel.fromJson((b['panel'] as Map).cast<String, dynamic>())
          : null,
    );
  }

  /// Создать VLESS+Reality инбаунд на подключённой панели 3x-ui и сделать его
  /// активным. body: {remark, port, sni, dest?, flow, fingerprint}. Возвращает
  /// обновлённую панель (с проставленным inbound).
  static Future<SellerPanel> sellerCreateInbound(
      int panelId, Map<String, dynamic> body) async {
    final r = await http
        .post(Uri.parse('$kApiBase/seller/panels/$panelId/inbounds/create'),
            headers: _authHeaders, body: jsonEncode(body))
        .timeout(const Duration(seconds: 25));
    _check(r);
    final b = jsonDecode(r.body) as Map<String, dynamic>;
    return SellerPanel.fromJson((b['panel'] as Map).cast<String, dynamic>());
  }

  /// Список всех инбаундов панели 3x-ui с пометкой активного (active: true).
  static Future<List<PanelInbound>> sellerPanelInbounds(int panelId) async {
    final r = await http
        .get(Uri.parse('$kApiBase/seller/panels/$panelId/inbounds'),
            headers: _authHeadersNoBody)
        .timeout(const Duration(seconds: 25));
    _check(r);
    final b = jsonDecode(r.body) as Map<String, dynamic>;
    return ((b['inbounds'] as List?) ?? [])
        .map((e) => PanelInbound.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Сделать инбаунд активным (для выдачи персональных UUID). Возвращает панель.
  static Future<SellerPanel> sellerSelectInbound(int panelId, Object inboundId) async {
    final r = await http
        .post(Uri.parse('$kApiBase/seller/panels/$panelId/inbounds/select'),
            headers: _authHeaders, body: jsonEncode({'inbound_id': inboundId}))
        .timeout(const Duration(seconds: 25));
    _check(r);
    final b = jsonDecode(r.body) as Map<String, dynamic>;
    return SellerPanel.fromJson((b['panel'] as Map).cast<String, dynamic>());
  }

  /// Удалить инбаунд с панели 3x-ui. Возвращает обновлённую панель.
  static Future<SellerPanel> sellerDeleteInbound(int panelId, Object inboundId) async {
    final req = http.Request(
        'DELETE', Uri.parse('$kApiBase/seller/panels/$panelId/inbounds/$inboundId'));
    req.headers.addAll(_authHeaders);
    final streamed = await req.send().timeout(const Duration(seconds: 25));
    final r = await http.Response.fromStream(streamed);
    _check(r);
    final b = jsonDecode(r.body) as Map<String, dynamic>;
    return SellerPanel.fromJson((b['panel'] as Map).cast<String, dynamic>());
  }

  /// Удалить панель продавца (привязанные группы вернутся к общему nodes_json).
  static Future<void> sellerDeletePanel(int panelId) async {
    final req = http.Request('DELETE', Uri.parse('$kApiBase/seller/panels/$panelId'));
    req.headers.addAll(_authHeaders);
    final streamed = await req.send().timeout(_timeout);
    final r = await http.Response.fromStream(streamed);
    _check(r);
  }

  /// Сгенерировать seller-ключ (только админ). Возвращает полный ключ.
  static Future<String> adminCreateSellerKey({String note = ''}) async {
    final r = await http
        .post(Uri.parse('$kApiBase/admin/seller_keys'),
            headers: _authHeaders, body: jsonEncode({'note': note}))
        .timeout(_timeout);
    _check(r);
    return (jsonDecode(r.body) as Map)['key'] as String;
  }

  /// Список seller-ключей (только админ).
  static Future<List<AdminSellerKey>> adminSellerKeys() async {
    final r = await http
        .get(Uri.parse('$kApiBase/admin/seller_keys'), headers: _authHeadersNoBody)
        .timeout(_timeout);
    _check(r);
    final b = jsonDecode(r.body) as Map<String, dynamic>;
    return ((b['keys'] as List?) ?? [])
        .map((e) => AdminSellerKey.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Отозвать seller-ключ (только админ).
  static Future<void> adminRevokeSellerKey(int keyId) async {
    final req = http.Request('DELETE', Uri.parse('$kApiBase/admin/seller_keys/$keyId'));
    req.headers.addAll(_authHeaders);
    final streamed = await req.send().timeout(_timeout);
    final r = await http.Response.fromStream(streamed);
    _check(r);
  }

  /// Заявки на вывод (только админ).
  static Future<List<AdminSellerPayout>> adminSellerPayouts() async {
    final r = await http
        .get(Uri.parse('$kApiBase/admin/seller_payouts'), headers: _authHeadersNoBody)
        .timeout(_timeout);
    _check(r);
    final b = jsonDecode(r.body) as Map<String, dynamic>;
    return ((b['payouts'] as List?) ?? [])
        .map((e) => AdminSellerPayout.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Отметить заявку выплаченной/отклонённой (только админ).
  static Future<void> adminProcessPayout({
    required int payoutId,
    required String status, // 'paid' | 'rejected'
  }) async {
    final req = http.Request('PATCH', Uri.parse('$kApiBase/admin/seller_payouts/$payoutId'));
    req.headers.addAll(_authHeaders);
    req.body = jsonEncode({'status': status});
    final streamed = await req.send().timeout(_timeout);
    final r = await http.Response.fromStream(streamed);
    _check(r);
  }

  /// Админ: выдать (amount>0) или списать (amount<0) баланс по username/id.
  /// Возвращает итоговый баланс юзера.
  static Future<double> adminGrantBalance({
    String username = '',
    int? telegramId,
    required double amountRub,
  }) async {
    final r = await http
        .post(
          Uri.parse('$kApiBase/admin/balance'),
          headers: _authHeaders,
          body: jsonEncode({
            if (username.isNotEmpty) 'username': username,
            if (telegramId != null) 'telegram_id': telegramId,
            'amount_rub': amountRub,
          }),
        )
        .timeout(_timeout);
    _check(r);
    return ((jsonDecode(r.body) as Map)['balance_rub'] as num?)?.toDouble() ?? 0;
  }

  /// Админ: список ненулевых балансов.
  static Future<List<UserBalanceEntry>> adminBalances() async {
    final r = await http
        .get(Uri.parse('$kApiBase/admin/balances'), headers: _authHeadersNoBody)
        .timeout(_timeout);
    _check(r);
    final b = jsonDecode(r.body) as Map<String, dynamic>;
    return ((b['balances'] as List?) ?? [])
        .map((e) => UserBalanceEntry.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
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

  // ─── Анонсы / интерактивные модалки ──────────────────────────────────────

  /// Активные анонсы для текущего юзера (поллится на старте).
  static Future<List<Announcement>> announcementsActive() async {
    final r = await http
        .get(Uri.parse('$kApiBase/announcements/active'), headers: _authHeadersNoBody)
        .timeout(_timeout);
    _check(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    return ((body['items'] as List?) ?? [])
        .map((e) => Announcement.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Отметить, что юзер увидел анонс (чтобы once больше не показывался).
  static Future<void> markSeen(String announcementId) async {
    final r = await http
        .post(Uri.parse('$kApiBase/announcements/$announcementId/seen'),
            headers: _authHeaders)
        .timeout(_timeout);
    _check(r);
  }

  /// Список всех анонсов для управления (только админ).
  static Future<List<Announcement>> adminListAnnouncements() async {
    final r = await http
        .get(Uri.parse('$kApiBase/admin/announcements'), headers: _authHeadersNoBody)
        .timeout(_timeout);
    _check(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    return ((body['items'] as List?) ?? [])
        .map((e) => Announcement.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Создать анонс. Возвращает id.
  static Future<String> createAnnouncement(Announcement a) async {
    final r = await http
        .post(Uri.parse('$kApiBase/admin/announcements'),
            headers: _authHeaders, body: jsonEncode(a.toRequestJson()))
        .timeout(_timeout);
    _check(r);
    return (jsonDecode(r.body) as Map)['id'] as String;
  }

  /// Обновить анонс (передаётся всё тело; бэкенд берёт только присланные поля).
  static Future<void> updateAnnouncement(Announcement a) async {
    final req = http.Request('PATCH', Uri.parse('$kApiBase/admin/announcements/${a.id}'));
    req.headers.addAll(_authHeaders);
    req.body = jsonEncode(a.toRequestJson());
    final streamed = await req.send().timeout(_timeout);
    final r = await http.Response.fromStream(streamed);
    _check(r);
  }

  static Future<void> deleteAnnouncement(String announcementId) async {
    final req =
        http.Request('DELETE', Uri.parse('$kApiBase/admin/announcements/$announcementId'));
    req.headers.addAll(_authHeaders);
    final streamed = await req.send().timeout(_timeout);
    final r = await http.Response.fromStream(streamed);
    _check(r);
  }

  /// Поиск юзеров для таргетинга «выбранным» (только админ).
  static Future<List<AnnTargetUser>> searchUsers(String query, {int limit = 30}) async {
    final qp = {'q': query, 'limit': '$limit'};
    final r = await http
        .get(Uri.parse('$kApiBase/admin/users/search').replace(queryParameters: qp),
            headers: _authHeadersNoBody)
        .timeout(_timeout);
    _check(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    return ((body['items'] as List?) ?? [])
        .map((e) => AnnTargetUser.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
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

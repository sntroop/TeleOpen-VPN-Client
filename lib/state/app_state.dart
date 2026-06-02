// lib/state/app_state.dart
//
// Глобальное состояние приложения (ChangeNotifier) + мост к нативному
// VpnService. Раньше всё это жило одним ~600-строчным классом в main.dart.
// Теперь поля и базовый жизненный цикл — здесь, а логика по доменам разнесена
// по part-файлам (extension'ы на AppState в той же библиотеке, поэтому им
// доступны приватные поля/методы). Поведение не менялось.
//
//   app_state_groups.dart        — VPN-группы (CRUD, load/save, избранное)
//   app_state_mtproto.dart       — MTProto-прокси и их группы
//   app_state_user.dart          — пользователь, JWT, per-app proxy
//   app_state_connection.dart    — connect/disconnect, активная нода, сессии
//   app_state_subscriptions.dart — подписки и ручное добавление нод
//   app_state_ping.dart          — пинг нод

library app_state;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../vpn_bridge.dart';
import '../models/vpn_node.dart';
import '../models/per_app_proxy.dart';
import '../models/per_app_preset.dart';
import '../models/mtproto_proxy.dart';
import '../models/market.dart';
import '../logic/parsers.dart';
import '../logic/subscriptions.dart';
import '../logic/crash_log.dart';
import '../logic/ping.dart';
import '../logic/connectivity_probe.dart';
import '../logic/failover.dart';
import '../logic/hysteria2.dart';
import '../logic/market_api.dart';
import '../logic/secure_store.dart';
import '../screens/statistics_screen.dart';
import 'app_settings.dart';
import 'vpn_status.dart';

export 'app_settings.dart';
export 'vpn_status.dart';

part 'app_state_groups.dart';
part 'app_state_mtproto.dart';
part 'app_state_user.dart';
part 'app_state_connection.dart';
part 'app_state_subscriptions.dart';
part 'app_state_ping.dart';
part 'app_state_failover.dart';

/// Базовый класс: держит все поля и базовый жизненный цикл (таймер, dispose).
/// Доменная логика подмешивается mixin'ами ниже (все — `on AppStateBase`,
/// поэтому им доступны эти поля и protected `notifyListeners()`).
abstract class AppStateBase extends ChangeNotifier {
  final SharedPreferences prefs;
  final VpnBridge bridge = VpnBridge();

  VpnStatus status = VpnStatus.stopped;
  VpnNode? activeNode;
  List<VpnGroup> groups = [];
  List<MtProtoProxyGroup> mtProtoGroups = [];
  Set<String> favoriteIds = {};
  AppSettings settings;
  PerAppProxySettings perApp;
  List<PerAppPreset> perAppPresets = [];
  TgUser? currentUser;
  Duration connectionDuration = Duration.zero;
  VpnStats currentStats = VpnStats.zero;
  Timer? _timer;
  String? lastError;
  bool _pinging = false;
  bool get isPinging => _pinging;

  // ═════ История сессий ═════
  DateTime? _sessionStart;

  // ═════ Пинг ═════
  Timer? _pingNotifyTimer;

  // ═════ Автообновление подписок ═════
  Timer? _subRefreshTimer;

  // ═════ Проактивная проба связи ═════
  Timer? _probeTimer;
  bool _probeInFlight = false;
  final ProbeDecider _probeDecider = ProbeDecider();
  static const Duration _probeInterval = Duration(seconds: 25);

  // ═════ Failover ═════
  // Контроллер живёт в базе, чтобы и AppStateConnection, и AppStateFailover
  // (которые не видят друг друга напрямую) работали с одним состоянием.
  final FailoverController _failover = FailoverController();

  AppStateBase(this.prefs)
      : settings = AppSettings.fromPrefs(prefs),
        perApp = _loadPerApp(prefs);

  static PerAppProxySettings _loadPerApp(SharedPreferences p) {
    final s = p.getString('per_app_proxy');
    if (s == null || s.isEmpty) return PerAppProxySettings();
    try {
      final m = (jsonDecode(s) as Map).cast<String, dynamic>();
      return PerAppProxySettings.fromJson(m);
    } catch (_) {
      return PerAppProxySettings();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    connectionDuration = Duration.zero;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      connectionDuration += const Duration(seconds: 1);
      notifyListeners();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    connectionDuration = Duration.zero;
  }

  // ── Проактивная проба связи ──────────────────────────────────────────────

  void _startProbe() {
    _probeDecider.reset();
    _probeTimer?.cancel();
    _probeTimer = Timer.periodic(_probeInterval, (_) => _runProbe());
  }

  void _stopProbe() {
    _probeTimer?.cancel();
    _probeTimer = null;
    _probeInFlight = false;
    _probeDecider.reset();
  }

  Future<void> _runProbe() async {
    if (_probeInFlight) return; // throttle: не накладываем пробы
    if (status != VpnStatus.connected) return;
    final node = activeNode;
    if (node == null) return;

    _probeInFlight = true;
    try {
      final alive = await _probeOnce(node);
      final shouldAct = _probeDecider.recordResult(alive);
      if (shouldAct) _onConnectivityLost();
    } finally {
      _probeInFlight = false;
    }
  }

  /// Одна проба: TCP до ноды ИЛИ успешный DNS-резолв = связь жива.
  Future<bool> _probeOnce(VpnNode node) async {
    final tcp = await TcpPing.ping(node.address, node.port,
        timeout: const Duration(seconds: 3));
    if (tcp != null) return true;
    // TCP до ноды мог не пройти (UDP-протоколы, фильтрация порта) — проверим
    // фактический выход в сеть через DNS-резолв нейтрального домена.
    try {
      final r = await InternetAddress.lookup('cloudflare.com')
          .timeout(const Duration(seconds: 3));
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Связь подтверждённо мертва (порог промахов достигнут).
  /// Реализуется в AppStateFailover; базовая реализация — no-op.
  void _onConnectivityLost() {}

  // ── Методы, реализуемые доменными mixin'ами ──────────────────────────────
  // Объявлены здесь абстрактно, чтобы один mixin мог вызвать метод другого
  // (mixin'ы видят только AppStateBase, но не друг друга напрямую).
  void _saveGroups();                                          // AppStateGroups
  Future<void> disconnect();                                   // AppStateConnection
  Future<void> connect(VpnNode node);                          // AppStateConnection
  void addMtProtoProxy(MtProtoProxy proxy, {String? toGroupId}); // AppStateMtProto
  Future<void> _tryFailover({required String failedId});       // AppStateFailover
  Future<void> refreshAllSubscriptions();                      // AppStateSubscriptions
  // Перенастроить таймер автообновления подписок под текущие settings.
  // Реализуется в AppState (видит и settings, и mixin подписок).
  void reconfigureSubscriptionAutoUpdate();

  @override
  void dispose() {
    _timer?.cancel();
    _probeTimer?.cancel();
    _subRefreshTimer?.cancel();
    bridge.dispose();
    super.dispose();
  }
}

class AppState extends AppStateBase
    with
        AppStateGroups,
        AppStateMtProto,
        AppStateUser,
        AppStateConnection,
        AppStateSubscriptions,
        AppStatePing,
        AppStateFailover {
  AppState(super.prefs) {
    _loadFavorites();
    _loadMtProtoGroups();
    _loadUser();
    _loadPerAppPresets();
    _initBridge();
    // HIGH-5: ноды и секреты-настройки теперь в зашифрованном хранилище —
    // загрузка асинхронна. autoConnect стартует только после загрузки групп.
    // ignore: discarded_futures
    _bootstrapSecure();
  }

  Future<void> _bootstrapSecure() async {
    await _loadGroups();         // secure storage + миграция старого prefs-ключа
    await _loadSecureSettings(); // ec_secret/port_auth: миграция в Keystore
    notifyListeners();
    reconfigureSubscriptionAutoUpdate(); // запустить таймер автообновления подписок
    if (settings.autoConnect) await _autoConnect();
  }

  /// Перенастраивает таймер автообновления подписок под текущие settings.
  /// Вызывается после загрузки групп и при каждом изменении настроек.
  @override
  void reconfigureSubscriptionAutoUpdate() {
    _subRefreshTimer?.cancel();
    _subRefreshTimer = null;
    if (!settings.subAutoUpdate || settings.subUpdateHours <= 0) return;

    final interval = Duration(hours: settings.subUpdateHours);
    // Догоняем пропущенное окно: если с прошлого обновления прошло больше
    // интервала (или его не было) — обновляем сразу.
    final last = prefs.getInt('last_sub_refresh') ?? 0;
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - last;
    if (last == 0 || elapsedMs >= interval.inMilliseconds) {
      // ignore: discarded_futures
      refreshAllSubscriptions();
    }
    _subRefreshTimer = Timer.periodic(interval, (_) {
      // ignore: discarded_futures
      refreshAllSubscriptions();
    });
  }

  /// Подтягивает ec_secret/port_auth из защищённого хранилища в settings и
  /// одноразово мигрирует старые plaintext-значения из prefs (s_ecSecret/
  /// s_portAuth), после чего удаляет их из prefs.
  Future<void> _loadSecureSettings() async {
    try {
      // Миграция старых plaintext-ключей.
      for (final pair in const [
        ('s_ecSecret', 'ec_secret'),
        ('s_portAuth', 'port_auth'),
      ]) {
        final legacy = prefs.getString(pair.$1);
        if (legacy != null && legacy.isNotEmpty && legacy != 'Не менять') {
          await SecureStore.writeSecret(pair.$2, legacy);
        }
        await prefs.remove(pair.$1);
      }
      final ec = await SecureStore.readSecret('ec_secret');
      final pa = await SecureStore.readSecret('port_auth');
      if (ec != null && ec.isNotEmpty) settings.ecSecret = ec;
      if (pa != null && pa.isNotEmpty) settings.portAuth = pa;
      notifyListeners();
    } catch (e) {
      debugPrint('AppState._loadSecureSettings: $e');
    }
  }

  void _loadFavorites() {
    favoriteIds = prefs.getStringList('favorites')?.toSet() ?? {};
  }

  Future<void> _initBridge() async {
    await bridge.init(
      onStatus: (s) {
        final ev = parseNativeStatus(s);
        final newStatus = ev.status;
        if (status != newStatus) {
          status = newStatus;
          if (newStatus == VpnStatus.connected) {
            _startTimer();
            _sessionStart = DateTime.now();
            _startProbe();
            _resetFailover(); // успешная сессия → новый чистый эпизод
          } else {
            // Сессия уже сохранена в disconnect() — просто чистим
            _sessionStart = null;
            _stopTimer();
            _stopProbe();
            currentStats = VpnStats.zero;
          }
          notifyListeners();
        }
        // Внезапный обрыв (натив прислал DROPPED) → пробуем failover,
        // даже если статус формально уже был не connected.
        if (ev.unexpectedDrop) {
          final id = activeNode?.id;
          if (id != null) {
            // ignore: discarded_futures
            _tryFailover(failedId: id);
          }
        }
      },
      onStats: (s) {
        currentStats = s;
        notifyListeners();
      },
    );
    // Запушить сохранённый конфиг в ядро, чтобы первый коннект уже учитывал
    // все DNS/Meta/External Controller тоггл, выставленные пользователем.
    // ignore: discarded_futures
    bridge.applyCoreConfig(settings.toCoreConfig());
  }

  Future<void> _autoConnect() async {
    final lastId = prefs.getString('last_active_node');
    if (lastId == null) return;
    final node = _findNode(lastId);
    if (node != null) await connect(node);
  }

  VpnNode? _findNode(String id) {
    for (final g in groups) {
      for (final n in g.nodes) {
        if (n.id == id) return n;
      }
    }
    return null;
  }

  // ═════ Настройки ═════

  void updateSettings(AppSettings s) {
    settings = s;
    s.save(prefs);
    // HIGH-5: секреты (ec_secret/port_auth) не пишутся в prefs из save() —
    // храним их только в зашифрованном хранилище.
    if (s.ecSecret.isNotEmpty && s.ecSecret != 'Не менять') {
      // ignore: discarded_futures
      SecureStore.writeSecret('ec_secret', s.ecSecret);
    }
    if (s.portAuth.isNotEmpty && s.portAuth != 'Не менять') {
      // ignore: discarded_futures
      SecureStore.writeSecret('port_auth', s.portAuth);
    }
    notifyListeners();
    // Применяем "горячо" — ядро/нативщина решает, нужен ли рестарт.
    // Не await: UI не должен моргать на каждом тоггле.
    // ignore: discarded_futures
    bridge.applyCoreConfig(s.toCoreConfig());
    // Тумблер/интервал автообновления подписок мог измениться — перезапускаем.
    reconfigureSubscriptionAutoUpdate();
  }
}

class AppStateScope extends StatefulWidget {
  final Widget child;
  final SharedPreferences prefs;
  const AppStateScope({super.key, required this.child, required this.prefs});

  static AppState of(BuildContext context, {bool listen = true}) {
    if (listen) {
      final s = context.dependOnInheritedWidgetOfExactType<_AppStateInherited>();
      assert(s != null, 'AppStateScope not found');
      return s!.state;
    } else {
      final s = context.getInheritedWidgetOfExactType<_AppStateInherited>();
      assert(s != null, 'AppStateScope not found');
      return s!.state;
    }
  }

  @override
  State<AppStateScope> createState() => _AppStateScopeState();
}

class _AppStateScopeState extends State<AppStateScope> {
  late AppState _state;

  @override
  void initState() {
    super.initState();
    _state = AppState(widget.prefs);
    _state.addListener(_onChange);
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    _state.removeListener(_onChange);
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AppStateInherited(state: _state, child: widget.child);
  }
}

class _AppStateInherited extends InheritedWidget {
  final AppState state;
  const _AppStateInherited({required this.state, required super.child});

  @override
  bool updateShouldNotify(_AppStateInherited oldWidget) => true;
}

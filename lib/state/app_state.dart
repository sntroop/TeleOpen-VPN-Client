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

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../vpn_bridge.dart';
import '../models/vpn_node.dart';
import '../models/per_app_proxy.dart';
import '../models/mtproto_proxy.dart';
import '../models/market.dart';
import '../logic/parsers.dart';
import '../logic/subscriptions.dart';
import '../logic/crash_log.dart';
import '../logic/ping.dart';
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

  // ── Методы, реализуемые доменными mixin'ами ──────────────────────────────
  // Объявлены здесь абстрактно, чтобы один mixin мог вызвать метод другого
  // (mixin'ы видят только AppStateBase, но не друг друга напрямую).
  void _saveGroups();                                          // AppStateGroups
  Future<void> disconnect();                                   // AppStateConnection
  void addMtProtoProxy(MtProtoProxy proxy, {String? toGroupId}); // AppStateMtProto

  @override
  void dispose() {
    _timer?.cancel();
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
        AppStatePing {
  AppState(super.prefs) {
    _loadFavorites();
    _loadGroups();
    _loadMtProtoGroups();
    _loadUser();
    _initBridge();
    if (settings.autoConnect) _autoConnect();
  }

  void _loadFavorites() {
    favoriteIds = prefs.getStringList('favorites')?.toSet() ?? {};
  }

  Future<void> _initBridge() async {
    await bridge.init(
      onStatus: (s) {
        final newStatus = switch (s.toUpperCase()) {
          'CONNECTING' => VpnStatus.connecting,
          'CONNECTED'  => VpnStatus.connected,
          _            => VpnStatus.stopped,
        };
        if (status != newStatus) {
          status = newStatus;
          if (newStatus == VpnStatus.connected) {
            _startTimer();
            _sessionStart = DateTime.now();
          } else {
            // Сессия уже сохранена в disconnect() — просто чистим
            _sessionStart = null;
            _stopTimer();
            currentStats = VpnStats.zero;
          }
          notifyListeners();
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
    notifyListeners();
    // Применяем "горячо" — ядро/нативщина решает, нужен ли рестарт.
    // Не await: UI не должен моргать на каждом тоггле.
    // ignore: discarded_futures
    bridge.applyCoreConfig(s.toCoreConfig());
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

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ios_theme.dart';
import '../main.dart';
import '../models/vpn_node.dart';
import '../logic/geolocation.dart';

class _GeoNode {
  final VpnNode node;
  final String country;
  final String city;
  _GeoNode({required this.node, required this.country, required this.city});
}

class _ServerCluster {
  final double lat;
  final double lng;
  final List<_GeoNode> items;
  _ServerCluster({required this.lat, required this.lng, required this.items});

  
  static String keyFor(double lat, double lng) {
    final lt = (lat * 2).round() / 2;
    final ln = (lng * 2).round() / 2;
    return '$lt,$ln';
  }

  bool get isMulti => items.length > 1;

  String get title {
    if (items.isEmpty) return '';
    final c = items.first.country;
    return c.isEmpty ? items.first.node.name : c;
  }

  String? get subtitle {
    if (items.isEmpty) return null;
    final city = items.first.city;
    if (isMulti) return '${items.length} серверов${city.isNotEmpty ? " · $city" : ""}';
    return city.isNotEmpty ? city : null;
  }
}

class WorldMapScreen extends StatefulWidget {
  const WorldMapScreen({super.key});

  @override
  State<WorldMapScreen> createState() => _WorldMapScreenState();
}

class _WorldMapScreenState extends State<WorldMapScreen> with TickerProviderStateMixin {
  static const double _initialZoom = 1.8;
  static const double _focusLat = 50.0;
  static const double _focusLng = 15.0;
  static const double _markerScreenSize = 14.0;

  double _mapAspect = 2.0;
  bool _imageLoaded = false;

  final List<_ServerCluster> _clusters = [];
  final Map<String, _ServerCluster> _clusterIndex = {};

  bool _loading = true;
  _ServerCluster? _selected;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  final TransformationController _transform = TransformationController();
  bool _mapInit = false;
  double _currentScale = 1.0;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _transform.addListener(() {
      final s = _transform.value.getMaxScaleOnAxis();
      if ((s - _currentScale).abs() > 0.001) {
        setState(() => _currentScale = s);
      }
    });
    _loadImageAspect();
    _resolve();
  }

  Future<void> _loadImageAspect() async {
    const img = AssetImage('assets/world_map.png');
    final stream = img.resolve(ImageConfiguration.empty);
    final completer = Completer<ui.Image>();
    stream.addListener(ImageStreamListener((info, _) {
      completer.complete(info.image);
    }, onError: (e, _) {
      completer.completeError(e);
    }));
    try {
      final image = await completer.future;
      if (!mounted) return;
      setState(() {
        _mapAspect = image.width / image.height;
        _imageLoaded = true;
        _mapInit = false;
      });
    } catch (_) {
      if (mounted) setState(() => _imageLoaded = true);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _transform.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    final state = AppStateScope.of(context, listen: false);
    final seen = <String>{};
    final tasks = <Future<void>>[];
    for (final g in state.groups) {
      for (final n in g.nodes) {
        if (n.address.isEmpty || seen.contains(n.address)) continue;
        seen.add(n.address);
        tasks.add(_addPin(n));
      }
    }
    await Future.wait(tasks);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addPin(VpnNode n) async {
    final p = await Geolocation.resolve(n.address);
    if (!mounted || p == null) return;
    final key = _ServerCluster.keyFor(p.lat, p.lng);
    setState(() {
      var cluster = _clusterIndex[key];
      if (cluster == null) {
        cluster = _ServerCluster(lat: p.lat, lng: p.lng, items: []);
        _clusterIndex[key] = cluster;
        _clusters.add(cluster);
      }
      if (!cluster.items.any((g) => g.node.id == n.id)) {
        cluster.items.add(_GeoNode(node: n, country: p.country, city: p.city));
      }
    });
  }

  
  static Offset _project(double lat, double lng) {
    final x = (lng + 180) / 360;
    final clampedLat = lat.clamp(-85.05112878, 85.05112878);
    final latRad = clampedLat * math.pi / 180.0;
    final mercY = (1 - (math.log(math.tan((math.pi / 4) + (latRad / 2)))) / math.pi) / 2;
    return Offset(x.clamp(0.0, 1.0), mercY.clamp(0.0, 1.0));
  }

  void _initMapTransform(Size view, double mapW, double mapH) {
    if (_mapInit) return;
    if (!_imageLoaded) return;
    _mapInit = true;
    final baseScale = view.height / mapH;
    final scale = baseScale * _initialZoom;
    final focus = _project(_focusLat, _focusLng);
    final focusPxX = focus.dx * mapW;
    final focusPxY = focus.dy * mapH;
    final dx = view.width / 2 - scale * focusPxX;
    final dy = view.height / 2 - scale * focusPxY;
    _transform.value = Matrix4.identity()..translate(dx, dy)..scale(scale);
    _currentScale = scale;
  }

  void _onClusterTap(_ServerCluster cluster) {
    if (cluster.isMulti) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _ClusterPickerSheet(
          cluster: cluster,
          state: AppStateScope.of(context, listen: false),
        ),
      );
    } else {
      setState(() => _selected = cluster);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final state = AppStateScope.of(context);
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: c.bgPrimary,
      extendBodyBehindAppBar: true,
      extendBody: true,
      body: Stack(children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (_, constraints) {
              final view = Size(constraints.maxWidth, constraints.maxHeight);
              final mapW = view.width;
              final mapH = mapW / _mapAspect;
              _initMapTransform(view, mapW, mapH);

              final markerSizeInChild = _markerScreenSize / _currentScale;

              return InteractiveViewer(
                transformationController: _transform,
                minScale: 0.3,
                maxScale: 8.0,
                constrained: false,
                boundaryMargin: EdgeInsets.zero,
                child: SizedBox(
                  width: mapW,
                  height: mapH,
                  child: Stack(children: [
                    Positioned.fill(
                      child: Image.asset(
                        'assets/world_map.png',
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                    ..._clusters.map((cluster) {
                      final p = _project(cluster.lat, cluster.lng);
                      final x = p.dx * mapW;
                      final y = p.dy * mapH;
                      final active = cluster.items.any((g) =>
                          state.activeNode?.id == g.node.id && state.status == VpnStatus.connected);
                      final isSelected = _selected == cluster;
                      final effSize = markerSizeInChild * (cluster.isMulti ? 1.3 : 1.0);
                      return Positioned(
                        left: x - effSize / 2,
                        top:  y - effSize / 2,
                        width: effSize,
                        height: effSize,
                        child: GestureDetector(
                          onTap: () => _onClusterTap(cluster),
                          child: AnimatedBuilder(
                            animation: _pulseAnim,
                            builder: (_, __) => _Marker(
                              size: effSize, c: c,
                              active: active, selected: isSelected, pulse: _pulseAnim.value,
                              badgeCount: cluster.isMulti ? cluster.items.length : null,
                              currentScale: _currentScale,
                            ),
                          ),
                        ),
                      );
                    }),
                  ]),
                ),
              );
            },
          ),
        ),

        Positioned(
          top: topInset + 4, left: 0, right: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
            child: Row(children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: c.bgSecondary.withValues(alpha: 0.85), shape: BoxShape.circle),
                  child: Icon(CupertinoIcons.chevron_back, size: 20, color: c.textPrimary),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: c.bgSecondary.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(IosShapes.radiusPill),
                ),
                child: Row(children: [
                  Icon(CupertinoIcons.globe, size: 14, color: c.textPrimary),
                  const SizedBox(width: 6),
                  Text(_totalNodesText(), style: t.textStyles.footnote),
                ]),
              ),
            ]),
          ),
        ),

        if (_loading)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 24, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: c.bgSecondary,
                  borderRadius: BorderRadius.circular(IosShapes.radiusPill),
                  boxShadow: IosShadows.card(c),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 14, height: 14, child: CupertinoActivityIndicator(color: c.textPrimary)),
                  const SizedBox(width: 10),
                  Text('Геолокация серверов…', style: t.textStyles.footnote),
                ]),
              ),
            ),
          ),

        if (_selected != null && !_selected!.isMulti)
          Positioned(
            left: 16, right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: _ServerPopup(
              cluster: _selected!,
              state: state,
              onClose: () => setState(() => _selected = null),
            ),
          ),
      ]),
    );
  }

  String _totalNodesText() {
    int total = 0;
    for (final c in _clusters) {
      total += c.items.length;
    }
    return '$total серверов';
  }
}

class _Marker extends StatelessWidget {
  final double size;
  final IosColors c;
  final bool active;
  final bool selected;
  final double pulse;
  final int? badgeCount;
  final double currentScale;
  const _Marker({
    required this.size,
    required this.c,
    required this.active,
    required this.selected,
    required this.pulse,
    required this.currentScale,
    this.badgeCount,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? c.green : (selected ? c.textPrimary : c.red);
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        if (active)
          Container(
            width: size + (size * 1.2) * pulse,
            height: size + (size * 1.2) * pulse,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.25 * (1 - pulse)),
              shape: BoxShape.circle,
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: size * 0.15),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: size * 0.3)],
          ),
        ),
        
        if (badgeCount != null)
          Center(
            child: Transform.scale(
              scale: 1 / currentScale,
              child: Text(
                '$badgeCount',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  shadows: [Shadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 2)],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ServerPopup extends StatelessWidget {
  final _ServerCluster cluster;
  final AppState state;
  final VoidCallback onClose;
  const _ServerPopup({required this.cluster, required this.state, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final node = cluster.items.first.node;
    final isActive = state.activeNode?.id == node.id && state.status == VpnStatus.connected;
    final isConnecting = state.activeNode?.id == node.id && state.status == VpnStatus.connecting;

    return IosCard(
      padding: EdgeInsets.zero,
      radius: IosShapes.radiusXLarge,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cluster.title, style: t.textStyles.title3, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (cluster.subtitle != null)
                Text(cluster.subtitle!, style: t.textStyles.subheadline.copyWith(color: c.textSecondary)),
            ])),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(CupertinoIcons.xmark_circle_fill, size: 24, color: c.textTertiary),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(children: [
            Text(node.protocolLabel,
              style: t.textStyles.caption1.copyWith(color: c.textSecondary, letterSpacing: 0.5)),
            const SizedBox(width: 8),
            Container(width: 3, height: 3, decoration: BoxDecoration(color: c.textTertiary, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(child: Text(node.address,
              style: t.textStyles.caption1.copyWith(color: c.textTertiary, fontFamily: 'monospace'),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: IosButton(
            label: isActive ? 'Отключиться' : (isConnecting ? 'Подключение…' : 'Подключиться'),
            style: isActive ? IosButtonStyle.destructive : IosButtonStyle.primary,
            loading: isConnecting,
            onPressed: () {
              if (isActive) {
                state.disconnect();
              } else {
                state.connect(node);
              }
              onClose();
            },
          ),
        ),
      ]),
    );
  }
}

class _ClusterPickerSheet extends StatelessWidget {
  final _ServerCluster cluster;
  final AppState state;
  const _ClusterPickerSheet({required this.cluster, required this.state});

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return Container(
      margin: EdgeInsets.fromLTRB(8, 0, 8, MediaQuery.of(context).padding.bottom + 8),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      decoration: BoxDecoration(
        color: c.bgSecondary,
        borderRadius: IosShapes.continuous(IosShapes.radiusXLarge),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 6),
            width: 36, height: 4,
            decoration: BoxDecoration(color: c.textQuaternary, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(cluster.title, style: t.textStyles.headline),
                  if (cluster.subtitle != null)
                    Text(cluster.subtitle!,
                      style: t.textStyles.footnote.copyWith(color: c.textSecondary)),
                ]),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Icon(CupertinoIcons.xmark_circle_fill, size: 28, color: c.textQuaternary),
              ),
            ]),
          ),
          const SizedBox(height: 4),
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              physics: const BouncingScrollPhysics(),
              shrinkWrap: true,
              itemCount: cluster.items.length,
              separatorBuilder: (_, __) => Container(
                margin: const EdgeInsets.only(left: 16),
                height: 0.5, color: c.separator,
              ),
              itemBuilder: (_, i) {
                final geo = cluster.items[i];
                final n = geo.node;
                final isActive = state.activeNode?.id == n.id && state.status == VpnStatus.connected;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.of(context).pop();
                    if (isActive) {
                      state.disconnect();
                    } else {
                      state.connect(n);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(children: [
                      Container(
                        width: 8, height: 8,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: isActive ? c.green : c.textTertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(n.name, style: t.textStyles.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Row(children: [
                            Text(n.protocolLabel,
                              style: t.textStyles.caption2.copyWith(color: c.textTertiary, letterSpacing: 0.5)),
                            const SizedBox(width: 6),
                            Container(width: 3, height: 3, decoration: BoxDecoration(color: c.textTertiary, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Text(n.pingMs != null ? '${n.pingMs} ms' : '- ms',
                              style: t.textStyles.caption1.copyWith(color: c.textTertiary)),
                          ]),
                        ]),
                      ),
                      Icon(
                        isActive ? CupertinoIcons.stop_circle : CupertinoIcons.chevron_right,
                        size: 18, color: isActive ? c.red : c.textTertiary,
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

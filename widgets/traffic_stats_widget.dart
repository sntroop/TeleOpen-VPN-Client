import 'dart:collection';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ios_theme.dart';
import '../main.dart';
import '../vpn_bridge.dart';

class TrafficStatsWidget extends StatefulWidget {
  const TrafficStatsWidget({super.key});

  @override
  State<TrafficStatsWidget> createState() => _TrafficStatsWidgetState();
}

class _TrafficStatsWidgetState extends State<TrafficStatsWidget> {
  
  final Queue<int> _rxHistory = Queue<int>();
  final Queue<int> _txHistory = Queue<int>();
  static const _historyLimit = 30;
  VpnStats _last = VpnStats.zero;

  void _ingest(VpnStats s) {
    if (s.uptimeMs == _last.uptimeMs) return;
    _rxHistory.add(s.rxRate);
    _txHistory.add(s.txRate);
    while (_rxHistory.length > _historyLimit) _rxHistory.removeFirst();
    while (_txHistory.length > _historyLimit) _txHistory.removeFirst();
    _last = s;
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final state = AppStateScope.of(context);
    final s = state.currentStats;

    
    if (state.status != VpnStatus.connected) {
      
      if (_rxHistory.isNotEmpty || _txHistory.isNotEmpty) {
        _rxHistory.clear();
        _txHistory.clear();
        _last = VpnStats.zero;
      }
      return const SizedBox.shrink();
    }

    _ingest(s);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.bgSecondary,
        borderRadius: IosShapes.continuous(IosShapes.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _statColumn(
                t, c,
                label: 'Скачано',
                rate: s.rxRate, total: s.rxBytes,
                arrow: '↓', color: c.green,
              )),
              const SizedBox(width: 16),
              Expanded(child: _statColumn(
                t, c,
                label: 'Отправлено',
                rate: s.txRate, total: s.txBytes,
                arrow: '↑', color: c.blue,
              )),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: _Sparkline(
              rxSeries: _rxHistory.toList(),
              txSeries: _txHistory.toList(),
              rxColor: c.green,
              txColor: c.blue,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Сессия: ${_formatDuration(s.uptimeMs)}',
            style: t.textStyles.caption1.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _statColumn(IosThemeData t, IosColors c, {
    required String label, required int rate, required int total,
    required String arrow, required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.textStyles.caption1.copyWith(color: c.textSecondary)),
        const SizedBox(height: 2),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(text: '$arrow ', style: t.textStyles.headline.copyWith(color: color)),
              TextSpan(text: _formatRate(rate), style: t.textStyles.headline.copyWith(color: c.textPrimary)),
            ],
          ),
        ),
        Text(
          'всего ${_formatBytes(total)}',
          style: t.textStyles.caption1.copyWith(color: c.textSecondary),
        ),
      ],
    );
  }
}

String _formatRate(int bytesPerSec) {
  if (bytesPerSec < 1024) return '$bytesPerSec B/s';
  if (bytesPerSec < 1024 * 1024) {
    return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
  }
  return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(2)} MB/s';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String _formatDuration(int ms) {
  final s = ms ~/ 1000;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  if (h > 0) {
    return '${h}ч ${m.toString().padLeft(2, '0')}м ${sec.toString().padLeft(2, '0')}с';
  }
  return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

class _Sparkline extends StatelessWidget {
  final List<int> rxSeries;
  final List<int> txSeries;
  final Color rxColor;
  final Color txColor;
  const _Sparkline({
    required this.rxSeries,
    required this.txSeries,
    required this.rxColor,
    required this.txColor,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _SparklinePainter(rxSeries, txSeries, rxColor, txColor),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<int> rx;
  final List<int> tx;
  final Color rxColor;
  final Color txColor;
  _SparklinePainter(this.rx, this.tx, this.rxColor, this.txColor);

  @override
  void paint(Canvas canvas, Size size) {
    if (rx.isEmpty && tx.isEmpty) return;
    
    final maxVal = [
      ...rx, ...tx, 1,  
    ].reduce((a, b) => a > b ? a : b);
    _drawSeries(canvas, size, rx, rxColor, maxVal);
    _drawSeries(canvas, size, tx, txColor, maxVal);
  }

  void _drawSeries(Canvas canvas, Size size, List<int> data, Color color, int maxVal) {
    if (data.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();
    final stepX = data.length > 1 ? size.width / (data.length - 1) : size.width;
    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final y = size.height - (data[i] / maxVal) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fill);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparklinePainter o) =>
      o.rx != rx || o.tx != tx;
}

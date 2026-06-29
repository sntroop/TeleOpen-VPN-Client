// lib/screens/statistics/tiles.dart
// Тайлы списка: топ-сервер (_NodeStatTile) и сессия (_SessionTile),
// плюс агрегат _NodeStat. part of statistics_screen.

part of '../statistics_screen.dart';

class _NodeStat {
  final String name;
  final String protocol;
  final int sessions;
  final int totalBytes;
  final int totalSec;

  const _NodeStat({
    required this.name,
    required this.protocol,
    required this.sessions,
    required this.totalBytes,
    required this.totalSec,
  });
}

class _NodeStatTile extends StatelessWidget {
  final IosThemeData t;
  final IosColors c;
  final _NodeStat node;
  final double ratio;
  final int rank;

  const _NodeStatTile({
    required this.t,
    required this.c,
    required this.node,
    required this.ratio,
    required this.rank,
  });

  @override
  Widget build(BuildContext context) {
    final rankColors = [c.orange, c.textSecondary, c.fill, c.fill, c.fill];
    final rankColor = rankColors[math.min(rank - 1, rankColors.length - 1)];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28, height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rankColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$rank',
                  style: t.textStyles.footnote.copyWith(
                    color: rankColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.name,
                      style: t.textStyles.body.copyWith(color: c.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${node.protocol} · ${node.sessions} ${_sessionsLabel(node.sessions)}',
                      style: t.textStyles.caption1.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatBytes(node.totalBytes),
                style: t.textStyles.body.copyWith(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 4,
              backgroundColor: c.fill,
              valueColor: AlwaysStoppedAnimation<Color>(c.blue),
            ),
          ),
        ],
      ),
    );
  }

  String _sessionsLabel(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'сессия';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) return 'сессии';
    return 'сессий';
  }
}

class _SessionTile extends StatelessWidget {
  final IosThemeData t;
  final IosColors c;
  final SessionRecord session;

  const _SessionTile({required this.t, required this.c, required this.session});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final diff = now.difference(session.startedAt);
    final timeLabel = diff.inDays >= 1
        ? '${diff.inDays}д назад'
        : diff.inHours >= 1
            ? '${diff.inHours}ч назад'
            : '${diff.inMinutes}м назад';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: c.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(CupertinoIcons.wifi, size: 18, color: c.blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.nodeName,
                  style: t.textStyles.body.copyWith(color: c.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${session.protocol} · ${_formatDuration(session.durationSec)}',
                  style: t.textStyles.caption1.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatBytes(session.totalBytes),
                style: t.textStyles.footnote.copyWith(color: c.textPrimary),
              ),
              Text(
                timeLabel,
                style: t.textStyles.caption2.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

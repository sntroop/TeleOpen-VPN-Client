// lib/screens/statistics/format.dart
// Форматтеры байт/длительности, общие для экрана и его виджетов.
// part of statistics_screen.

part of '../statistics_screen.dart';

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String _formatDuration(int sec) {
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = sec % 60;
  if (h > 0) return '$hч ${m.toString().padLeft(2, '0')}м';
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String _formatDurationLong(int sec) {
  if (sec < 60) return '$sec с';
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  if (h >= 24) {
    final d = h ~/ 24;
    final rh = h % 24;
    return '$dд $rhч';
  }
  if (h > 0) return '$hч $mм';
  return '$mм';
}

// lib/models/per_app_preset.dart
//
// Именованный пресет split-tunnel: набор пакетов приложений, которые
// гонятся через VPN (allowlist). Применяется одним тапом → заполняет
// PerAppProxySettings.includedPackages.
//
// Модель allowlist-only (как PerAppProxySettings): пресет задаёт, КАКИЕ
// приложения идут через VPN. «Только банк напрямую» (denylist) этой моделью
// не выражается — требует нативной поддержки addDisallowedApplication.

import 'dart:convert';

class PerAppPreset {
  final String name;
  final List<String> packages;

  /// Встроенные пресеты помечаются, чтобы их нельзя было удалить из UI.
  final bool builtin;

  const PerAppPreset({
    required this.name,
    required this.packages,
    this.builtin = false,
  });

  PerAppPreset copyWith({String? name, List<String>? packages, bool? builtin}) =>
      PerAppPreset(
        name: name ?? this.name,
        packages: packages ?? List.from(this.packages),
        builtin: builtin ?? this.builtin,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'packages': packages,
        'builtin': builtin,
      };

  factory PerAppPreset.fromJson(Map<String, dynamic> j) => PerAppPreset(
        name: (j['name'] ?? '') as String,
        packages: List<String>.from(j['packages'] ?? const []),
        builtin: (j['builtin'] ?? false) as bool,
      );

  /// Встроенные пресеты, которыми засевается список при первом запуске.
  static List<PerAppPreset> defaults() => const [
        PerAppPreset(
          name: 'Мессенджеры',
          builtin: true,
          packages: [
            'org.telegram.messenger',
            'org.thunderdog.challegram',
            'com.whatsapp',
            'org.thoughtcrime.securesms', // Signal
          ],
        ),
      ];

  /// Сериализация списка пресетов в JSON-строку для SharedPreferences.
  static String encode(List<PerAppPreset> list) =>
      jsonEncode(list.map((p) => p.toJson()).toList());

  /// Десериализация; при битых данных возвращает пустой список.
  static List<PerAppPreset> decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map((m) => PerAppPreset.fromJson(m.cast<String, dynamic>()))
          .where((p) => p.name.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }
}

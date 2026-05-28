class PerAppProxySettings {
  bool enabled;
  List<String> includedPackages;

  PerAppProxySettings({this.enabled = false, List<String>? includedPackages})
      : includedPackages = includedPackages ?? [];

  PerAppProxySettings copyWith({bool? enabled, List<String>? includedPackages}) =>
      PerAppProxySettings(
        enabled: enabled ?? this.enabled,
        includedPackages: includedPackages ?? List.from(this.includedPackages),
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'includedPackages': includedPackages,
      };

  factory PerAppProxySettings.fromJson(Map<String, dynamic> j) => PerAppProxySettings(
        enabled: j['enabled'] ?? false,
        includedPackages: List<String>.from(j['includedPackages'] ?? []),
      );
}

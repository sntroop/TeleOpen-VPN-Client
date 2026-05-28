import 'package:flutter/material.dart';
import '../ios_theme.dart';

class UserTheme {
  final int? id;             
  final String name;
  final String mode;         
  final IosColors colors;
  final IosRadii radii;
  final IosBackground background;

  
  final int authorTelegramId;
  final String authorUsername;
  final String authorFirstName;
  final int installsCount;
  final DateTime? createdAt;

  const UserTheme({
    this.id,
    required this.name,
    required this.mode,
    required this.colors,
    this.radii = const IosRadii(),
    this.background = const IosBackground.solid(),
    this.authorTelegramId = 0,
    this.authorUsername = '',
    this.authorFirstName = '',
    this.installsCount = 0,
    this.createdAt,
  });

  Brightness get brightness =>
      mode == 'light' ? Brightness.light : Brightness.dark;

  
  IosThemeData toIosThemeData() => IosThemeData.custom(
        brightness: brightness,
        colors: colors,
        radii: radii,
        background: background,
        name: name,
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        'mode': mode,
        'colors': colors.toJson(),
        'radii': radii.toJson(),
        'background': background.toJson(),
      };

  factory UserTheme.fromJson(Map<String, dynamic> j) {
    final mode = (j['mode'] ?? 'dark').toString();
    final fallback = mode == 'light' ? IosColors.light : IosColors.dark;
    return UserTheme(
      id: j['id'] is int ? j['id'] as int : null,
      name: (j['name'] ?? 'Тема').toString(),
      mode: mode,
      colors: IosColors.fromJson(
        (j['colors'] as Map?)?.cast<String, dynamic>() ?? {},
        fallback: fallback,
      ),
      radii: IosRadii.fromJson(
          (j['radii'] as Map?)?.cast<String, dynamic>() ?? {}),
      background: IosBackground.fromJson(
          (j['background'] as Map?)?.cast<String, dynamic>() ?? {}),
      authorTelegramId: (j['author_telegram_id'] as num?)?.toInt() ?? 0,
      authorUsername: (j['author_username'] ?? '').toString(),
      authorFirstName: (j['author_first_name'] ?? '').toString(),
      installsCount: (j['installs_count'] as num?)?.toInt() ?? 0,
      createdAt: j['created_at'] != null
          ? DateTime.tryParse(j['created_at'].toString())
          : null,
    );
  }

  UserTheme copyWith({
    String? name,
    String? mode,
    IosColors? colors,
    IosRadii? radii,
    IosBackground? background,
  }) =>
      UserTheme(
        id: id,
        name: name ?? this.name,
        mode: mode ?? this.mode,
        colors: colors ?? this.colors,
        radii: radii ?? this.radii,
        background: background ?? this.background,
        authorTelegramId: authorTelegramId,
        authorUsername: authorUsername,
        authorFirstName: authorFirstName,
        installsCount: installsCount,
        createdAt: createdAt,
      );

  
  factory UserTheme.newDraft({String name = 'Моя тема', String mode = 'dark'}) {
    return UserTheme(
      name: name,
      mode: mode,
      colors: mode == 'light' ? IosColors.light : IosColors.dark,
    );
  }
}

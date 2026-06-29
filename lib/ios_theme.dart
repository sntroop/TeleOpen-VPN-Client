// lib/ios_theme.dart
//
// iOS 17/18 native design language for Flutter.
// Light + Dark palettes, reusable widgets matched to Apple HIG.
//
// Использование:
//   1) Оберни приложение в IosThemeScope.
//   2) Доступ к токенам: IosTheme.of(context).colors.bgPrimary, и т.д.
//   3) Используй компоненты: IosButton, IosSwitch, IosCard, IosField, IosSegment.
//
// Переключение темы:
//   IosThemeScope.of(context).toggle();
//   IosThemeScope.of(context).setMode(IosThemeMode.dark);
//
// ─────────────────────────────────────────────────────────────────────────────
// Этот файл — корень библиотеки `ios_theme`. Раньше всё (палитра, типографика,
// токены, scope и ~10 компонентов) лежало здесь одним ~1500-строчным файлом.
// Теперь оно разнесено по part-файлам в lib/ios_theme/ (и components/), а сам
// путь файла не изменился — поэтому существующие `import '.../ios_theme.dart'`
// продолжают видеть весь публичный API без правок.

library ios_theme;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 1–4: дизайн-токены и тема
part 'ios_theme/colors.dart';
part 'ios_theme/text_styles.dart';
part 'ios_theme/tokens.dart';
part 'ios_theme/theme_data.dart';
part 'ios_theme/theme_scope.dart';

// 5: компоненты
part 'ios_theme/components/button.dart';
part 'ios_theme/components/switch.dart';
part 'ios_theme/components/card.dart';
part 'ios_theme/components/field.dart';
part 'ios_theme/components/segment.dart';
part 'ios_theme/components/menu.dart';
part 'ios_theme/components/list.dart';
part 'ios_theme/components/dialog.dart';
part 'ios_theme/components/theme_toggle.dart';

// test/region_code_test.dart
//
// Проверяет парсинг двухбуквенного кода страны из строки региона.
// Код уходит в core_config (ключ region_code) и превращается нативкой
// в geoip-правило маршрутизации — важно, чтобы парсинг был устойчив.
import 'package:flutter_test/flutter_test.dart';
import 'package:my_vpn/state/app_settings.dart';

void main() {
  group('AppSettings.regionCodeOf', () {
    test('извлекает код из "Россия (ru)"', () {
      expect(AppSettings.regionCodeOf('Россия (ru)'), 'ru');
    });

    test('приводит к нижнему регистру', () {
      expect(AppSettings.regionCodeOf('United States (US)'), 'us');
    });

    test('без скобок → пустая строка', () {
      expect(AppSettings.regionCodeOf('Россия'), '');
    });

    test('пустой ввод → пустая строка', () {
      expect(AppSettings.regionCodeOf(''), '');
    });

    test('мусор в скобках (не 2 буквы) → пустая строка', () {
      expect(AppSettings.regionCodeOf('Хрень (123)'), '');
      expect(AppSettings.regionCodeOf('Хрень (russia)'), '');
    });

    test('берёт первое двухбуквенное совпадение', () {
      expect(AppSettings.regionCodeOf('Foo (de) Bar (fr)'), 'de');
    });
  });
}

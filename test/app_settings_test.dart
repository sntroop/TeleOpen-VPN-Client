// Юнит-тесты модели настроек (lib/state/app_settings.dart).
//
// toCoreConfig() сериализует настройки для нативного ядра (mihomo/clash.meta).
// Ключевой инвариант: sentinel-значение 'Не менять' и пустые пути НЕ должны
// попадать в конфиг (иначе перетёрли бы значения из подписки). Также проверяем
// независимость copy().

import 'package:flutter_test/flutter_test.dart';

import 'package:my_vpn/state/app_settings.dart';

void main() {
  group('toCoreConfig — фильтрация sentinel', () {
    test('строки "Не менять" не попадают в конфиг', () {
      final m = AppSettings().toCoreConfig(); // дефолты: масса 'Не менять'
      expect(m.containsKey('dns_nameserver'), isFalse);
      expect(m.containsKey('meta_unified_delay'), isFalse);
      expect(m.containsKey('ec_secret'), isFalse);
      // ни одно значение в map не должно быть равно sentinel
      expect(m.values.contains('Не менять'), isFalse);
    });

    test('пустые пути geoip/geosite не попадают', () {
      final m = AppSettings().toCoreConfig();
      expect(m.containsKey('meta_geoip_path'), isFalse);
      expect(m.containsKey('meta_geosite_path'), isFalse);
    });

    test('переопределённое строковое поле попадает в конфиг', () {
      final s = AppSettings(dnsEnhancedMode: 'fake-ip');
      final m = s.toCoreConfig();
      expect(m['dns_enhanced_mode'], 'fake-ip');
    });

    test('bool-поля всегда присутствуют', () {
      final m = AppSettings(killSwitch: true, useMux: false).toCoreConfig();
      expect(m['kill_switch'], true);
      expect(m['use_mux'], false);
      expect(m.containsKey('packet_analysis'), isTrue);
    });

    test('непустой путь geoip попадает', () {
      final m = AppSettings(metaGeoipPath: '/data/geoip.dat').toCoreConfig();
      expect(m['meta_geoip_path'], '/data/geoip.dat');
    });
  });

  group('copy', () {
    test('копия независима от оригинала', () {
      final original = AppSettings(killSwitch: false, dns: '1.1.1.1');
      final copy = AppSettings.copy(original);
      copy.killSwitch = true;
      copy.dns = '8.8.8.8';
      // оригинал не изменился
      expect(original.killSwitch, isFalse);
      expect(original.dns, '1.1.1.1');
      // копия получила новые значения
      expect(copy.killSwitch, isTrue);
      expect(copy.dns, '8.8.8.8');
    });

    test('копия переносит все поля корректно', () {
      final original = AppSettings(
        region: 'Германия (de)',
        metaGeoipPath: '/x/geoip.dat',
        dnsEnhancedMode: 'redir-host',
      );
      final copy = AppSettings.copy(original);
      expect(copy.region, 'Германия (de)');
      expect(copy.metaGeoipPath, '/x/geoip.dat');
      expect(copy.dnsEnhancedMode, 'redir-host');
    });
  });
}

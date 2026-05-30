// test/per_app_preset_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:my_vpn/models/per_app_preset.dart';

void main() {
  group('PerAppPreset сериализация', () {
    test('round-trip toJson/fromJson', () {
      const p = PerAppPreset(name: 'Игры', packages: ['com.a', 'com.b'], builtin: false);
      final back = PerAppPreset.fromJson(p.toJson());
      expect(back.name, 'Игры');
      expect(back.packages, ['com.a', 'com.b']);
      expect(back.builtin, false);
    });

    test('encode/decode списка', () {
      final list = [
        const PerAppPreset(name: 'A', packages: ['x']),
        const PerAppPreset(name: 'B', packages: ['y', 'z'], builtin: true),
      ];
      final decoded = PerAppPreset.decode(PerAppPreset.encode(list));
      expect(decoded.length, 2);
      expect(decoded[1].name, 'B');
      expect(decoded[1].builtin, true);
      expect(decoded[1].packages, ['y', 'z']);
    });

    test('decode битых данных → пустой список', () {
      expect(PerAppPreset.decode('не json'), isEmpty);
      expect(PerAppPreset.decode(null), isEmpty);
      expect(PerAppPreset.decode(''), isEmpty);
    });

    test('decode отбрасывает записи без имени', () {
      const raw = '[{"packages":["x"]},{"name":"ok","packages":["y"]}]';
      final decoded = PerAppPreset.decode(raw);
      expect(decoded.length, 1);
      expect(decoded.first.name, 'ok');
    });
  });

  group('PerAppPreset.defaults', () {
    test('содержит «Мессенджеры» и помечен builtin', () {
      final defs = PerAppPreset.defaults();
      expect(defs, isNotEmpty);
      final messengers = defs.firstWhere((p) => p.name == 'Мессенджеры');
      expect(messengers.builtin, true);
      expect(messengers.packages, contains('org.telegram.messenger'));
    });
  });
}

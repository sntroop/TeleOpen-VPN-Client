// Юнит-тесты разбора плана AI-фиксера (lib/logic/ai_fixer.dart).
//
// AI-фиксер применяет к настройкам план, присланный сервером. Безопасность
// держится на двух рубежах: (1) неизвестные типы действий схлопываются в
// no_change ещё на парсинге, (2) применение идёт только по белому списку полей.
// Здесь проверяем рубеж (1) — парсинг FixAction/FixPlan.

import 'package:flutter_test/flutter_test.dart';

import 'package:my_vpn/logic/ai_fixer.dart';

void main() {
  group('FixAction.fromJson', () {
    test('известный тип распознаётся', () {
      final a = FixAction.fromJson({
        'type': 'switch_setting',
        'key': 'useMux',
        'value': true,
        'label': 'Вкл mux',
        'explanation': 'почему',
      });
      expect(a.type, FixActionType.switch_setting);
      expect(a.key, 'useMux');
      expect(a.value, true);
    });

    test('неизвестный/мусорный тип → no_change (а не исключение)', () {
      final a = FixAction.fromJson({'type': 'rm -rf /', 'label': 'x'});
      expect(a.type, FixActionType.no_change);
    });

    test('отсутствующий type → no_change', () {
      final a = FixAction.fromJson({'label': 'x'});
      expect(a.type, FixActionType.no_change);
    });
  });

  group('FixPlan.fromJson', () {
    test('no_change отфильтровывается при наличии других действий', () {
      final plan = FixPlan.fromJson({
        'diagnosis': 'DPI',
        'confidence': 80,
        'actions': [
          {'type': 'switch_setting', 'key': 'packetAnalysis', 'value': true},
          {'type': 'garbage'}, // → no_change → должен быть отброшен
        ],
      });
      expect(plan.actions.length, 1);
      expect(plan.actions.first.type, FixActionType.switch_setting);
    });

    test('единственный no_change сохраняется (ИИ не нашёл причин)', () {
      final plan = FixPlan.fromJson({
        'diagnosis': 'всё ок',
        'confidence': 30,
        'actions': [
          {'type': 'no_change', 'label': 'ничего'},
        ],
      });
      expect(plan.actions.length, 1);
      expect(plan.actions.first.type, FixActionType.no_change);
    });

    test('confidence зажимается в 0..100', () {
      expect(FixPlan.fromJson({'confidence': 250, 'actions': []}).confidence, 100);
      expect(FixPlan.fromJson({'confidence': -10, 'actions': []}).confidence, 0);
    });

    test('пустой/битый ввод → дефолтный диагноз, пустой список', () {
      final plan = FixPlan.fromJson({});
      expect(plan.actions, isEmpty);
      expect(plan.diagnosis, isNotEmpty);
      expect(plan.confidence, 50);
    });
  });
}

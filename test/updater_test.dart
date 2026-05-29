// Юнит-тесты разбора ответа сервера обновлений (lib/logic/updater.dart).
//
// UpdateInfo.fromJson — вход для in-app self-update: отсюда берётся versionCode
// (решение «обновляться ли»), sha256 (проверка скачанного APK) и URL. Проверяем
// нормализацию sha256, склейку относительного URL и человекочитаемый размер.

import 'package:flutter_test/flutter_test.dart';

import 'package:my_vpn/logic/updater.dart';
import 'package:my_vpn/logic/market_api.dart' show kApiBase;

void main() {
  group('UpdateInfo.fromJson', () {
    test('парсит поля и приводит sha256 к нижнему регистру', () {
      final info = UpdateInfo.fromJson({
        'version_code': 5003,
        'version_name': '1.0.5',
        'changelog': 'fixes',
        'size': 1048576,
        'sha256': 'ABCDEF0123456789',
        'url': 'https://cdn.example.com/app.apk',
      });
      expect(info.versionCode, 5003);
      expect(info.versionName, '1.0.5');
      expect(info.sha256, 'abcdef0123456789'); // нормализован
      expect(info.url, 'https://cdn.example.com/app.apk'); // абсолютный — как есть
    });

    test('относительный url склеивается с kApiBase', () {
      final info = UpdateInfo.fromJson({
        'version_code': 1,
        'url': '/dl/teleopen.apk',
      });
      expect(info.url, '$kApiBase/dl/teleopen.apk');
    });

    test('отсутствующие необязательные поля → дефолты', () {
      final info = UpdateInfo.fromJson({'version_code': 42});
      expect(info.versionCode, 42);
      expect(info.versionName, '');
      expect(info.changelog, '');
      expect(info.size, 0);
      expect(info.sha256, '');
    });

    test('sizeHuman форматирует байты/КБ/МБ', () {
      UpdateInfo mk(int size) =>
          UpdateInfo.fromJson({'version_code': 1, 'size': size});
      expect(mk(512).sizeHuman, '512 B');
      expect(mk(2048).sizeHuman, '2.0 KB');
      expect(mk(3 * 1024 * 1024).sizeHuman, '3.0 MB');
    });
  });
}

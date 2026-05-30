// test/privacy_cert_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:my_vpn/logic/trust.dart';

void main() {
  group('TrustInfo.normalize', () {
    test('нижний регистр', () {
      expect(TrustInfo.normalize('AABBCC'), 'aabbcc');
    });
    test('убирает двоеточия и пробелы', () {
      expect(TrustInfo.normalize('AA:BB CC\tDD'), 'aabbccdd');
    });
  });

  group('TrustInfo.matches', () {
    const expected =
        'f8fc68a33ecef7accc9a51192cba45d34dc027e4615daa954b5007c9226b69b6';

    test('точное совпадение', () {
      expect(TrustInfo.matches(expected), isTrue);
    });
    test('совпадение при другом регистре и двоеточиях', () {
      final colonized =
          expected.toUpperCase().replaceAllMapped(RegExp('..'), (m) => '${m[0]}:');
      expect(TrustInfo.matches(colonized), isTrue);
    });
    test('mismatch для чужого хэша', () {
      expect(TrustInfo.matches('deadbeef'), isFalse);
    });
    test('mismatch для пустой строки', () {
      expect(TrustInfo.matches(''), isFalse);
    });
  });
}

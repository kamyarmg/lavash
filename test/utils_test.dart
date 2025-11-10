import 'package:flutter_test/flutter_test.dart';
import 'package:lavash/core/utils.dart';

void main() {
  group('toFaDigits', () {
    test('converts ascii digits inside string', () {
      expect(toFaDigits('0123456789'), '۰۱۲۳۴۵۶۷۸۹');
      expect(toFaDigits('a1b2c3'), 'a۱b۲c۳');
    });

    test('accepts non-string and converts via toString()', () {
      expect(toFaDigits(2025), '۲۰۲۵');
      expect(toFaDigits(0), '۰');
    });
  });
}

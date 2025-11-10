import 'package:flutter_test/flutter_test.dart';
import 'package:lavash/core/strings.dart';

void main() {
  group('Strings (basic)', () {
    test('fa language returns Persian labels', () {
      final s = Strings(AppLanguage.fa);
      expect(s.isFa, isTrue);
      expect(s.appTitle.contains('پازل'), isTrue);
      expect(s.abPickImage, 'عکس');
      expect(s.settingsDark, 'حالت تیره');
    });

    test('en language returns English labels', () {
      final s = Strings(AppLanguage.en);
      expect(s.isFa, isFalse);
      expect(
        s.appTitle.contains('Puzzle') || s.appTitle.contains('Lavash'),
        isTrue,
      );
      expect(s.abPickImage, 'Image');
      expect(s.settingsDark, 'Dark mode');
    });
  });
}

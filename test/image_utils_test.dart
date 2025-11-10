import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lavash/core/image_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('decodeUiImage throws on invalid data', () async {
    final invalid = Uint8List.fromList([0, 1, 2, 3]);
    expect(() async => await decodeUiImage(invalid), throwsA(isA<Exception>()));
  });
}

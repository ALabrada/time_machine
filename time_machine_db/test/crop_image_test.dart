import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:time_machine_db/time_machine_db.dart';

void main() {
  group('cropImage', () {
    test('calculates crop rectangle correctly', () {
      final result = cropImage(
        width: 1920,
        height: 1080,
        viewPort: Rectangle(0, 0, 1920, 1080),
        intersection: Rectangle(100, 50, 800, 600),
      );
      expect(result.left, 100);
      expect(result.top, 50);
      expect(result.width, 800);
      expect(result.height, 600);
    });

    test('handles viewport offset', () {
      final result = cropImage(
        width: 800,
        height: 600,
        viewPort: Rectangle(100, 100, 400, 300),
        intersection: Rectangle(150, 150, 200, 100),
      );
      expect(result.left, 100);
      expect(result.top, 100);
      expect(result.width, 400);
      expect(result.height, 200);
    });

    test('handles intersection outside viewport left', () {
      final result = cropImage(
        width: 800,
        height: 600,
        viewPort: Rectangle(100, 0, 400, 300),
        intersection: Rectangle(0, 0, 200, 300),
      );
      expect(result.left, 0);
      expect(result.top, 0);
      expect(result.width, 400);
      expect(result.height, 600);
    });

    test('rounds to integers', () {
      final result = cropImage(
        width: 100,
        height: 100,
        viewPort: Rectangle(0, 0, 3, 3),
        intersection: Rectangle(1, 1, 2, 2),
      );
      expect(result.left, 33);
      expect(result.top, 33);
      expect(result.width, 66);
      expect(result.height, 66);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:time_machine_db/time_machine_db.dart';

void main() {
  group('DateTimeConverter', () {
    final converter = DateTimeConverter();

    test('fromJson with int returns DateTime', () {
      final epoch = 1700000000000;
      final dt = converter.fromJson(epoch);
      expect(dt, DateTime.fromMillisecondsSinceEpoch(epoch));
    });

    test('fromJson with String returns parsed DateTime', () {
      final iso = '2024-01-15T10:30:00.000Z';
      final dt = converter.fromJson(iso);
      expect(dt, DateTime.parse(iso));
    });

    test('toJson returns millisecondsSinceEpoch', () {
      final dt = DateTime(2024, 1, 15, 10, 30);
      expect(converter.toJson(dt), dt.millisecondsSinceEpoch);
    });

    test('roundtrip preserves value', () {
      final original = DateTime(2024, 6, 15, 14, 30, 0);
      final json = converter.toJson(original);
      final restored = converter.fromJson(json);
      expect(restored, original);
    });
  });
}

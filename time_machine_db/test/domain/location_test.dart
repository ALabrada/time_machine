import 'package:flutter_test/flutter_test.dart';

import 'package:time_machine_db/time_machine_db.dart';

void main() {
  group('Location', () {
    test('fromJson creates Location correctly', () {
      final json = {'lat': 55.7558, 'lng': 37.6173};
      final location = Location.fromJson(json);
      expect(location.lat, 55.7558);
      expect(location.lng, 37.6173);
    });

    test('toJson returns correct map', () {
      final location = const Location(lat: 48.8566, lng: 2.3522);
      final json = location.toJson();
      expect(json['lat'], 48.8566);
      expect(json['lng'], 2.3522);
    });

    test('roundtrip preserves values', () {
      final original = const Location(lat: 40.7128, lng: -74.0060);
      final json = original.toJson();
      final restored = Location.fromJson(json);
      expect(restored.lat, original.lat);
      expect(restored.lng, original.lng);
    });
  });
}

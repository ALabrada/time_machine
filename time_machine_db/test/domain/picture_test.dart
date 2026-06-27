import 'package:flutter_test/flutter_test.dart';

import 'package:time_machine_db/time_machine_db.dart';

void main() {
  group('Picture', () {
    final now = DateTime(2024, 6, 15);

    Picture createSamplePicture({int? localId, DateTime? visitedAt}) {
      return Picture(
        id: 'pic_001',
        url: 'https://example.com/photo.jpg',
        latitude: 55.7558,
        longitude: 37.6173,
        localId: localId,
        provider: 'pastvu',
        previewUrl: 'https://example.com/thumb.jpg',
        description: 'A historic photo',
        altitude: 150.0,
        bearing: 90.0,
        time: '1910',
        margin: '10px',
        site: 'Moscow',
        visitedAt: visitedAt,
      );
    }

    test('fromJson creates Picture correctly', () {
      final json = {
        'id': 'pic_001',
        'url': 'https://example.com/photo.jpg',
        'latitude': 55.7558,
        'longitude': 37.6173,
        'provider': 'pastvu',
        'previewUrl': 'https://example.com/thumb.jpg',
        'description': 'A historic photo',
        'altitude': 150.0,
        'bearing': 90.0,
        'time': '1910',
        'margin': '10px',
        'site': 'Moscow',
        'visitedAt': now.millisecondsSinceEpoch,
      };
      final picture = Picture.fromJson(json);
      expect(picture.id, 'pic_001');
      expect(picture.url, 'https://example.com/photo.jpg');
      expect(picture.latitude, 55.7558);
      expect(picture.longitude, 37.6173);
      expect(picture.provider, 'pastvu');
      expect(picture.description, 'A historic photo');
      expect(picture.altitude, 150.0);
      expect(picture.bearing, 90.0);
      expect(picture.time, '1910');
      expect(picture.site, 'Moscow');
      expect(picture.visitedAt, now);
    });

    test('fromJson handles null fields', () {
      final json = {
        'id': 'pic_002',
        'url': 'https://example.com/photo2.jpg',
        'latitude': 48.8566,
        'longitude': 2.3522,
      };
      final picture = Picture.fromJson(json);
      expect(picture.id, 'pic_002');
      expect(picture.provider, isNull);
      expect(picture.description, isNull);
      expect(picture.altitude, isNull);
      expect(picture.visitedAt, isNull);
    });

    test('toJson returns correct map', () {
      final picture = createSamplePicture(visitedAt: now);
      final json = picture.toJson();
      expect(json['id'], 'pic_001');
      expect(json['url'], 'https://example.com/photo.jpg');
      expect(json['latitude'], 55.7558);
      expect(json['longitude'], 37.6173);
      expect(json['visitedAt'], now.millisecondsSinceEpoch);
    });

    test('location getter returns correct Location', () {
      final picture = createSamplePicture();
      final loc = picture.location;
      expect(loc.lat, 55.7558);
      expect(loc.lng, 37.6173);
    });

    test('location setter updates coordinates', () {
      final picture = createSamplePicture();
      picture.location = const Location(lat: 40.7128, lng: -74.0060);
      expect(picture.latitude, 40.7128);
      expect(picture.longitude, -74.0060);
    });

    test('text returns description with time', () {
      final picture = createSamplePicture();
      expect(picture.text, 'A historic photo (1910)');
    });

    test('text returns description only when time is null', () {
      final picture = Picture(
        id: 'pic_003',
        url: 'https://example.com/photo3.jpg',
        latitude: 0,
        longitude: 0,
        description: 'No date',
      );
      expect(picture.text, 'No date');
    });

    test('text returns empty string when all null', () {
      final picture = Picture(
        id: 'pic_004',
        url: 'https://example.com/photo4.jpg',
        latitude: 0,
        longitude: 0,
      );
      expect(picture.text, '');
    });

    test('roundtrip preserves values', () {
      final original = createSamplePicture(visitedAt: now);
      final json = original.toJson();
      final restored = Picture.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.url, original.url);
      expect(restored.latitude, original.latitude);
      expect(restored.longitude, original.longitude);
      expect(restored.provider, original.provider);
      expect(restored.visitedAt, original.visitedAt);
    });
  });
}

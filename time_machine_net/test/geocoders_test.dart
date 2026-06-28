import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_machine_db/domain/location.dart';
import 'package:time_machine_net/domain/place_info.dart';
import 'package:time_machine_net/services/geonames_geocoder.dart';
import 'package:time_machine_net/services/native_geocoder.dart';
import 'package:time_machine_net/services/osm_geocoder.dart';
import 'package:time_machine_net/services/yandex_geocoder.dart';

import 'mock_adapter.dart';

const nycLat = 40.7128;
const nycLng = -74.0060;

void main() {
  group('GeonamesGeocoder', () {
    late GeonamesGeocoder geocoder;
    late MockDioAdapter adapter;

    setUp(() {
      geocoder = GeonamesGeocoder(userName: 'test-user');
      adapter = MockDioAdapter();
      geocoder.dio.httpClientAdapter = adapter;
    });

    test('searchAddress decodes geonames matching raw API', () async {
      adapter.dataFor = (options) {
        expect(options.path, 'findNearbyJSON');
        expect(options.queryParameters['q'], 'New York, NY');
        return {
          'geonames': [
            {
              'lat': '40.7128',
              'lng': '-74.0060',
              'name': 'New York City',
              'countryName': 'United States',
            },
          ],
        };
      };

      final results = await geocoder.searchAddress('New York, NY');
      expect(results.length, 1);
      expect(results.first.name, 'New York City, United States');
      expect(results.first.lat, closeTo(40.7128, 0.001));
    });

    test('searchCoordinates decodes address matching raw API', () async {
      adapter.dataFor = (options) {
        expect(options.path, 'addressJSON');
        expect(options.queryParameters['lat'], '40.712800');
        return {
          'address': {
            'lat': '40.7128',
            'lng': '-74.0060',
            'name': 'New York City',
            'countryName': 'United States',
          },
        };
      };

      final results =
          await geocoder.searchCoordinates(Location(lat: nycLat, lng: nycLng));
      expect(results.length, 1);
      expect(results.first.name, 'New York City, United States');
    });

    test('searchAddress concatenates all address fields', () async {
      adapter.dataFor = (_) => {
        'geonames': [
          {
            'lat': '40.7484',
            'lng': '-73.9967',
            'name': 'Empire State Building',
            'houseNumber': '350',
            'street': '5th Ave',
            'locality': 'Manhattan',
            'adminName2': 'New York County',
            'adminName1': 'New York',
            'countryName': 'United States',
          },
        ],
      };

      final results = await geocoder.searchAddress('Empire State Building');
      expect(results.first.name,
          'Empire State Building, 350, 5th Ave, Manhattan, New York County, New York, United States');
    });
  });
}

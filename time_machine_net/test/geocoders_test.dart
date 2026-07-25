import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_machine_db/domain/location.dart';
import 'package:time_machine_net/domain/place_info.dart';
import 'package:time_machine_net/services/geonames_geocoder.dart';
import 'package:time_machine_net/services/native_geocoder.dart';
import 'package:time_machine_net/services/osm_geocoder.dart';
import 'package:time_machine_net/services/vkmaps_geocoder.dart';
import 'package:time_machine_net/services/yandex_geocoder.dart';

import 'mock_adapter.dart';

const nycLat = 40.7128;
const nycLng = -74.0060;

void main() {
  group('VKMapsGeocoder', () {
    late VKMapsGeocoder geocoder;
    late MockDioAdapter adapter;

    setUp(() {
      geocoder = VKMapsGeocoder(apiKey: 'test-key');
      adapter = MockDioAdapter();
      geocoder.dio.httpClientAdapter = adapter;
    });

    test('searchAddress decodes results matching raw API', () async {
      adapter.dataFor = (options) {
        expect(options.path, '/search');
        expect(options.queryParameters['q'], 'New York, NY');
        expect(options.queryParameters['api_key'], 'test-key');
        return {
          'results': [
            {
              'name': 'New York City',
              'pin': [-74.0060, 40.7128],
              'address_details': {
                'country': 'United States',
              },
            },
          ],
        };
      };

      final results = await geocoder.searchAddress('New York, NY');
      expect(results.length, 1);
      expect(results.first.name, 'New York City, United States');
      expect(results.first.lat, closeTo(40.7128, 0.001));
      expect(results.first.lng, closeTo(-74.0060, 0.001));
    });

    test('searchCoordinates uses lat,lng as query', () async {
      adapter.dataFor = (options) {
        expect(options.path, '/search');
        expect(options.queryParameters['q'], '40.712800,-74.006000');
        expect(options.queryParameters['api_key'], 'test-key');
        return {
          'results': [
            {
              'name': 'New York City',
              'pin': [-74.0060, 40.7128],
              'address_details': {
                'country': 'United States',
              },
            },
          ],
        };
      };

      final results =
          await geocoder.searchCoordinates(Location(lat: nycLat, lng: nycLng));
      expect(results.length, 1);
      expect(results.first.name, 'New York City, United States');
    });

    test('searchAddress concatenates all address fields', () async {
      adapter.dataFor = (_) => {
        'results': [
          {
            'name': 'Empire State Building',
            'pin': [-73.9967, 40.7484],
            'address_details': {
              'building': '350',
              'street': '5th Ave',
              'locality': 'Manhattan',
              'subregion': 'New York County',
              'region': 'New York',
              'country': 'United States',
            },
          },
        ],
      };

      final results = await geocoder.searchAddress('Empire State Building');
      expect(results.first.name,
          'Empire State Building, 350, 5th Ave, Manhattan, New York County, New York, United States');
    });

    test('searchAddress decodes multiple results', () async {
      adapter.dataFor = (_) => {
        'results': [
          {
            'name': 'First',
            'pin': [10.0, 20.0],
            'address_details': {'country': 'A'},
          },
          {
            'name': 'Second',
            'pin': [30.0, 40.0],
            'address_details': {'country': 'B'},
          },
        ],
      };

      final results = await geocoder.searchAddress('test');
      expect(results.length, 2);
      expect(results[0].name, 'First, A');
      expect(results[0].lat, 20.0);
      expect(results[0].lng, 10.0);
      expect(results[1].name, 'Second, B');
      expect(results[1].lat, 40.0);
      expect(results[1].lng, 30.0);
    });

    test('searchAddress returns empty list when API returns no results', () async {
      adapter.dataFor = (_) => {'results': []};

      final results = await geocoder.searchAddress('nowhere');
      expect(results, isEmpty);
    });

    test('searchAddress handles partial address_details', () async {
      adapter.dataFor = (_) => {
        'results': [
          {
            'name': 'Partial',
            'pin': [2.0, 1.0],
            'address_details': {
              'locality': 'City',
              'country': 'Country',
            },
          },
        ],
      };

      final results = await geocoder.searchAddress('partial');
      expect(results.first.name, 'Partial, City, Country');
    });

    test('searchAddress handles integer pin values', () async {
      adapter.dataFor = (_) => {
        'results': [
          {
            'name': 'Int Pin',
            'pin': [1, 2],
            'address_details': {'country': 'X'},
          },
        ],
      };

      final results = await geocoder.searchAddress('int pin');
      expect(results.first.lat, 2.0);
      expect(results.first.lng, 1.0);
    });

    test('searchAddress does not include api_key when apiKey is null', () async {
      final noKeyGeocoder = VKMapsGeocoder();
      noKeyGeocoder.dio.httpClientAdapter = adapter;
      adapter.dataFor = (options) {
        expect(options.queryParameters.containsKey('api_key'), false);
        return {'results': []};
      };

      await noKeyGeocoder.searchAddress('test');
    });

    test('searchAddress sends User-Agent header when userAgent is set', () async {
      final uaGeocoder = VKMapsGeocoder(
        apiKey: 'key',
        userAgent: 'test-app/1.0',
      );
      uaGeocoder.dio.httpClientAdapter = adapter;
      adapter.dataFor = (options) {
        expect(options.headers[HttpHeaders.userAgentHeader], 'test-app/1.0');
        return {'results': []};
      };

      await uaGeocoder.searchAddress('test');
    });

    test('searchCoordinates does not include api_key when apiKey is null', () async {
      final noKeyGeocoder = VKMapsGeocoder();
      noKeyGeocoder.dio.httpClientAdapter = adapter;
      adapter.dataFor = (options) {
        expect(options.queryParameters.containsKey('api_key'), false);
        return {'results': []};
      };

      await noKeyGeocoder.searchCoordinates(Location(lat: 1, lng: 2));
    });

    test('_decode handles sublocality field', () async {
      adapter.dataFor = (_) => {
        'results': [
          {
            'name': 'Place',
            'pin': [30.0, 40.0],
            'address_details': {
              'sublocality': 'Subdistrict',
              'country': 'Country',
            },
          },
        ],
      };

      final results = await geocoder.searchAddress('place');
      expect(results.first.name, 'Place, Subdistrict, Country');
    });
  });

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
        expect(options.path, '/searchJSON');
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
        expect(options.path, '/findNearbyJSON');
        expect(options.queryParameters['lat'], '40.712800');
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

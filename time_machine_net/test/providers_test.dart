import 'package:flutter_test/flutter_test.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/domain/area.dart';
import 'package:time_machine_net/services/history_pin_provider.dart';
import 'package:time_machine_net/services/pastvu_provider.dart';
import 'package:time_machine_net/services/retro_photos_provider.dart';
import 'package:time_machine_net/services/russia_in_photo_provider.dart';
import 'package:time_machine_net/services/sepia_town_provider.dart';

import 'mock_adapter.dart';

const nycLat = 40.7128;
const nycLng = -74.0060;

Area nycArea({double? zoom}) => Area(
      minLat: 40.7120,
      minLng: -74.0070,
      maxLat: 40.7136,
      maxLng: -74.0050,
      zoom: zoom,
    );

Location nycLocation() => Location(lat: nycLat, lng: nycLng);

void main() {
  group('PastVuProvider', () {
    late PastVuProvider provider;
    late MockDioAdapter adapter;

    setUp(() {
      provider = PastVuProvider(userAgent: 'TimeMachineTest/1.0');
      adapter = MockDioAdapter();
      provider.dio.httpClientAdapter = adapter;
    });

    test('findIn matches raw PastVu API response structure', () async {
      adapter.dataFor = (options) {
        return {
          'result': {
            'photos': [
              {
                'cid': 1021559,
                'file': '5/o/s/5os5u0kwm8f242a4n3.jpg',
                'title': 'Smith & Gray Co. Building, Broadway & Warren Street',
                'geo': [40.71279, -74.006022],
                'year': 1910,
                'dir': 'nw',
              },
            ],
          },
        };
      };

      final pictures = await provider.findIn(
        area: nycArea(zoom: 15),
        startDate: DateTime(1900),
        endDate: DateTime(1920),
      );

      expect(pictures.length, 1);
      final pic = pictures.first;
      expect(pic.id, '1021559');
      expect(pic.url, 'https://pastvu.com/_p/a/5/o/s/5os5u0kwm8f242a4n3.jpg');
      expect(pic.previewUrl,
          'https://pastvu.com/_p/h/5/o/s/5os5u0kwm8f242a4n3.jpg');
      expect(pic.description,
          'Smith & Gray Co. Building, Broadway & Warren Street');
      expect(pic.latitude, closeTo(40.71279, 0.00001));
      expect(pic.longitude, closeTo(-74.006022, 0.00001));
      expect(pic.bearing, 315);
      expect(pic.time, '1910');
      expect(pic.site, 'https://pastvu.com/p/1021559');
    });

    test('findNear matches raw PastVu API response for NYC', () async {
      adapter.dataFor = (options) {
        return {
          'result': {
            'photos': [
              {
                'cid': 1021559,
                'file': '5/o/s/5os5u0kwm8f242a4n3.jpg',
                'title': 'Smith & Gray Co. Building, Broadway & Warren Street',
                'geo': [40.71279, -74.006022],
                'year': 1910,
                'dir': 'nw',
              },
              {
                'cid': 2231539,
                'file': 'some/other/path.jpg',
                'title': 'Lower Manhattan',
                'geo': [40.7075, -74.0023],
                'year': 1905,
                'year2': 1915,
                'dir': 'n',
              },
            ],
          },
        };
      };

      final pictures =
          await provider.findNear(location: nycLocation(), radius: 5000);

      expect(pictures.length, 2);
      expect(pictures[0].latitude, closeTo(40.71279, 0.00001));
      expect(pictures[1].time, '1905-1915');
      expect(pictures[1].bearing, 0);
    });

    test('findNear returns empty for radius > 1000000', () async {
      final pictures =
          await provider.findNear(location: nycLocation(), radius: 1000001);
      expect(pictures, isEmpty);
    });

    test('findIn handles no photos gracefully', () async {
      adapter.dataFor = (_) => {'result': {'photos': []}};
      final pictures = await provider.findIn(area: nycArea(zoom: 15));
      expect(pictures, isEmpty);
    });
  });

  group('RetroPhotosProvider', () {
    late RetroPhotosProvider provider;
    late MockDioAdapter adapter;

    setUp(() {
      provider = RetroPhotosProvider(userAgent: 'TimeMachineTest/1.0');
      adapter = MockDioAdapter();
      provider.dio.httpClientAdapter = adapter;
    });

    test('findIn decodes items matching raw API response', () async {
      adapter.dataFor = (options) {
        if (options.path == '/api/geo_template/') {
          return {
            'rest': [
              {
                'id': 5001,
                'position': {'type': 'Point', 'coordinates': [-74.0060, 40.7128]},
              },
            ],
          };
        }
        if (options.path == '/api/template/5001/') {
          return {
            'title': 'NYC Retro Photo',
            'image': {
              'file_fullscreen': 'https://img.re.photos/full/5001.jpg',
              'file_thumb': 'https://img.re.photos/thumb/5001.jpg',
              'creation_date': '1920',
            },
          };
        }
        return null;
      };

      final pictures = await provider.findIn(area: nycArea());
      expect(pictures.length, 1);
      expect(pictures.first.description, 'NYC Retro Photo');
      expect(pictures.first.latitude, closeTo(40.7128, 0.001));
      expect(pictures.first.longitude, closeTo(-74.0060, 0.001));
    });
  });

  group('HistoryPinProvider', () {
    late HistoryPinProvider provider;
    late MockDioAdapter adapter;

    setUp(() {
      provider = HistoryPinProvider(userAgent: 'TimeMachineTest/1.0');
      adapter = MockDioAdapter();
      provider.dio.httpClientAdapter = adapter;
    });

    test('findIn decodes pin/photo items matching raw API', () async {
      adapter.dataFor = (_) => {
        'results': [
          {
            'id': 3001,
            'node_type': 'pin',
            'type': 'photo',
            'caption': 'Old NYC Building',
            'date': '1915',
            'location': {'lat': 40.7128, 'lng': -74.0060},
            'display': {'content': '/img/nyc1.jpg'},
          },
        ],
      };

      final pictures = await provider.findIn(area: nycArea());
      expect(pictures.length, 1);
      expect(pictures.first.description, 'Old NYC Building');
      expect(pictures.first.latitude, closeTo(40.7128, 0.001));
      expect(pictures.first.longitude, closeTo(-74.0060, 0.001));
      expect(pictures.first.url, 'https://www.historypin.org/img/nyc1.jpg');
    });

    test('findIn filters non-pin and non-photo items', () async {
      adapter.dataFor = (_) => {
        'results': [
          {
            'id': 4001,
            'node_type': 'audio',
            'type': 'photo',
            'caption': 'audio',
            'location': {'lat': 40.7128, 'lng': -74.0060},
            'image': '/a.jpg',
          },
          {
            'id': 4002,
            'node_type': 'pin',
            'type': 'video',
            'caption': 'video',
            'location': {'lat': 40.7128, 'lng': -74.0060},
            'image': '/b.jpg',
          },
          {
            'id': 4003,
            'node_type': 'pin',
            'type': 'photo',
            'caption': 'valid',
            'location': {'lat': 40.7128, 'lng': -74.0060},
            'image': '/c.jpg',
          },
        ],
      };

      final pictures = await provider.findIn(area: nycArea());
      expect(pictures.length, 1);
      expect(pictures.first.id, '4003');
    });
  });

  group('RussiaInPhotoProvider', () {
    late RussiaInPhotoProvider provider;
    late MockDioAdapter adapter;

    setUp(() {
      provider = RussiaInPhotoProvider(userAgent: 'TimeMachineTest/1.0');
      adapter = MockDioAdapter();
      provider.dio.httpClientAdapter = adapter;
    });

    test('findIn expands photos_count matching raw API', () async {
      adapter.dataFor = (_) => {
        'results': [
          {
            'photo': {'id': 6001, 'url': 'https://russia.example/6001.jpg'},
            'lat': 40.7128,
            'lon': -74.0060,
            'photos_count': 2,
            'geohash': 'dr5reg',
          },
          {
            'photo': {'id': 6002, 'url': 'https://russia.example/6002.jpg'},
            'lat': 40.7061,
            'lon': -73.9969,
            'photos_count': 1,
          },
        ],
      };

      final pictures = await provider.findIn(area: nycArea());
      expect(pictures.length, 3);
      expect(pictures[0].id, '6001');
      expect(pictures[1].id, '6001');
      expect(pictures[2].id, '6002');
    });
  });

  group('SepiaTownProvider', () {
    late SepiaTownProvider provider;
    late MockDioAdapter adapter;

    setUp(() {
      provider = SepiaTownProvider(userAgent: 'TimeMachineTest/1.0');
      adapter = MockDioAdapter();
      provider.dio.httpClientAdapter = adapter;
    });

    test('findIn decodes items matching raw API response', () async {
      adapter.dataFor = (_) => [
        {
          'artifact_id': 7001,
          'title': 'Sepia NYC',
          'file_large_image_path': '/images/large/7001.jpg',
          'file_preview_image_path': '/images/medium/7001.jpg',
          'latitude': 40.7128,
          'longitude': -74.0060,
          'vantage': 'NE',
        },
      ];

      final pictures = await provider.findIn(area: nycArea(zoom: 15));
      expect(pictures.length, 1);
      expect(pictures.first.id, '7001');
      expect(pictures.first.description, 'Sepia NYC');
      expect(pictures.first.latitude, closeTo(40.7128, 0.001));
      expect(pictures.first.bearing, 45);
      expect(pictures.first.site, 'https://www.sepiatown.com/7001');
    });

    test('findIn uses fallback paths when direct paths absent', () async {
      adapter.dataFor = (_) => [
        {
          'artifact_id': 7002,
          'title': 'Fallback Test',
          'file_extension': 'png',
          'latitude': 40.7061,
          'longitude': -73.9969,
        },
      ];

      final pictures = await provider.findIn(area: nycArea(zoom: 15));
      expect(pictures.first.url,
          'https://www.sepiatown.com/archives/images/large/7002_large.png');
      expect(pictures.first.previewUrl,
          'https://www.sepiatown.com/archives/images/medium/7002_medium.png');
    });
  });
}

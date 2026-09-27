import 'package:dio/dio.dart';

import 'package:time_machine_core/domain/location.dart';
import 'package:time_machine_core/domain/place_info.dart';
import '../geo_math.dart';
import '../network_service.dart';

class YandexGeocoder implements GeocodingService {
  final dio = Dio(
    BaseOptions(baseUrl: 'https://geocode-maps.yandex.ru'),
  );
  String? apiKey;
  String? userAgent;

  YandexGeocoder({
    this.apiKey,
    this.userAgent,
    bool logRequests = false,
  }) {
    if (logRequests) {
      dio.interceptors.add(
        LogInterceptor(
          request: true,
          requestBody: true,
          responseBody: true,
          error: true,
        ),
      );
    }
  }

  @override
  Future<List<PlaceInfo>> searchAddress(String query) async {
    await dio.get('v1/',
      queryParameters: {
        if (apiKey != null)
          'apikey': apiKey!,
        'geocode': query,
        'format': 'json',
        'projection': 'web_mercator',
      },
      options: Options(
        headers: {
          if (userAgent != null)
            userAgentHeader: userAgent,
        },
      ),
    );
    throw Exception('Not implemented!');
  }

  @override
  Future<List<PlaceInfo>> searchCoordinates(Location location) async {
    await dio.get('v1/',
      queryParameters: {
        if (apiKey != null)
          'apikey': apiKey!,
        'geocode': '${location.lat.toStringAsFixed(6)},${location.lng.toStringAsFixed(6)}',
        'format': 'json',
        'projection': 'web_mercator',
      },
      options: Options(
        headers: {
          if (userAgent != null)
            userAgentHeader: userAgent,
        },
      ),
    );
    throw Exception('Not implemented!');
  }
}
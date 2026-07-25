import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:time_machine_db/domain/location.dart';
import 'package:time_machine_net/domain/place_info.dart';

import 'network_service.dart';

class VKMapsGeocoder implements GeocodingService {
  final dio = Dio(
    BaseOptions(baseUrl: 'https://maps.vk.com/api'),
  );
  String? apiKey;
  String? userAgent;

  VKMapsGeocoder({
    this.apiKey,
    this.userAgent,
  }) {
    if (!kReleaseMode) {
      dio.interceptors.add(
        LogInterceptor(
          request: true,
          requestBody: true,
          responseBody: true,
          error: true,
          logPrint: (o) => debugPrint(o.toString()),
        ),
      );
    }
  }

  @override
  Future<List<PlaceInfo>> searchAddress(String query) async {
    final response = await dio.get('/search',
      queryParameters: {
        'q': query,
        if (apiKey != null)
          'api_key': apiKey!,
      },
      options: Options(
        headers: {
          if (userAgent != null)
            HttpHeaders.userAgentHeader: userAgent,
        },
      ),
    );
    return [
      for (final item in response.data['results'] as List)
        _decode(item),
    ];
  }

  @override
  Future<List<PlaceInfo>> searchCoordinates(Location location) async {
    final response = await dio.get('/search',
      queryParameters: {
        'q': '${location.lat.toStringAsFixed(6)},${location.lng.toStringAsFixed(6)}',
        if (apiKey != null)
          'api_key': apiKey!,
      },
      options: Options(
        headers: {
          if (userAgent != null)
            HttpHeaders.userAgentHeader: userAgent,
        },
      ),
    );
    return [
      for (final item in response.data['results'] as List)
        _decode(item),
    ];
  }

  PlaceInfo _decode(dynamic address) {
    final pin = address['pin'] as List;
    final lng = (pin[0] as num).toDouble();
    final lat = (pin[1] as num).toDouble();
    final details = address['address_details'] as Map?;
    final name = [
      address['name'],
      details?['building'],
      details?['street'],
      details?['sublocality'],
      details?['locality'],
      details?['subregion'],
      details?['region'],
      details?['country'],
    ].whereType<String>().join(", ");
    return PlaceInfo(name: name, lat: lat, lng: lng);
  }
}

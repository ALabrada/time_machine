import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:time_machine_db/domain/location.dart';
import 'package:time_machine_net/domain/place_info.dart';

import 'network_service.dart';

class GeonamesGeocoder implements GeocodingService {
  final dio = Dio(
    BaseOptions(baseUrl: 'http://api.geonames.org'),
  );
  String? userAgent;
  String? userName;

  GeonamesGeocoder({
    this.userAgent,
    this.userName,
  }) {
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

  @override
  Future<List<PlaceInfo>> searchAddress(String query) async {
    final locale = Intl.defaultLocale;
    final response = await dio.get('findNearbyJSON',
      queryParameters: {
        'q': query,
        'formatted': 'true',
        'maxRows': 10,
        if (locale != null)
          'lang': locale,
        if (userName != null)
          'username': userName!,
      },
      options: Options(
        headers: {
          if (userAgent != null)
            HttpHeaders.userAgentHeader: userAgent,
        },
      ),
    );
    return [
      for (final item in response.data['geonames'] as List)
        _decode(item),
    ];
  }

  @override
  Future<List<PlaceInfo>> searchCoordinates(Location location) async {
    final response = await dio.get('addressJSON',
      queryParameters: {
        'lat': location.lat.toStringAsFixed(6),
        'lng': location.lng.toStringAsFixed(6),
        if (userName != null)
          'username': userName!,
      },
      options: Options(
        headers: {
          if (userAgent != null)
            HttpHeaders.userAgentHeader: userAgent,
        },
      ),
    );
    final address = _decode(response.data['address']);
    return [address];
  }

  PlaceInfo _decode(dynamic address) {
    final lat = double.parse(address['lat']);
    final lng = double.parse(address['lng']);
    final name = [
      address['name'],
      address['houseNumber'],
      address['street'],
      address['locality'],
      address['adminName2'],
      address['adminName1'],
      address['countryName'],
    ].whereType<String>().join(", ");
    return PlaceInfo(name: name, lat: lat, lng: lng);
  }
}
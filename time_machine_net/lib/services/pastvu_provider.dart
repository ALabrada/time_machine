import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:time_machine_net/domain/area.dart';
import 'package:time_machine_net/domain/location.dart';
import 'package:time_machine_net/domain/picture.dart';
import 'package:time_machine_net/services/network_service.dart';

class PastVuProvider implements DataProvider {
  final dio = Dio(
    BaseOptions(baseUrl: 'https://pastvu.com')
  );

  PastVuProvider() {
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
  Future<List<Picture>> findIn({
    required Area area,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final zoom = area.zoom;
    final params = {
      if (zoom != null)
        'z': zoom.toInt(),
      'geometry': {
        'type': 'Polygon',
        'coordinates': [
          [area.minLat, area.minLng],
          [area.maxLat, area.minLng],
          [area.maxLat, area.maxLng],
          [area.minLat, area.maxLng],
        ],
      },
      if (startDate != null)
        'year': startDate.year,
      if (endDate != null)
        'year2': endDate.year,
      if (zoom != null)
        'localWork': zoom >= 17 ? 1 : 0,
    };
    final response = await dio.get('/api2',
      queryParameters: {
        'method': 'photo.getByBounds',
        'params': json.encode(params),
      },
    );
    return [
      for (final item in response.data['result']['photos'] as List)
        _decode(item),
    ];
  }

  @override
  Future<List<Picture>> findNear({
    required Location location,
    required double radius,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (radius > 1000000) {
      return [];
    }

    final params = {
      'geo': [location.lat, location.lng],
      'distance': radius,
      if (startDate != null)
        'year': startDate.year,
      if (endDate != null)
        'year2': endDate.year,
    };
    final response = await dio.get('/api2',
      queryParameters: {
        'method': 'photo.giveNearestPhotos',
        'params': json.encode(params),
      },
    );
    return [
      for (final item in response.data['result']['photos'] as List)
        _decode(item),
    ];
  }

  Picture _decode(dynamic obj) {
    final baseUrl = dio.options.baseUrl;
    final path = obj['file'] as String;
    final coord = obj['geo'] as List;
    return Picture(
      id: obj['cid'].toString(),
      url: '$baseUrl/_p/a/$path',
      previewUrl: '$baseUrl/_p/h/$path',
      description: obj['title'] as String,
      location: Location(lat: coord[0] as double, lng: coord[1] as double),
      bearing: _decodeOrientation(obj['dir']?.toString()),
      time: obj['year']?.toString(),
    );
  }

  double? _decodeOrientation(String? direction) {
    switch (direction) {
      case 'n': return 0;
      case 'ne': return 45;
      case 'e': return 90;
      case 'se': return 135;
      case 's': return 180;
      case 'sw': return 225;
      case 'w': return 270;
      case 'nw': return 315;
      default: return null;
    }
  }
}
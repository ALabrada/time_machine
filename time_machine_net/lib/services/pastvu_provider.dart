import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/domain/area.dart';
import 'package:time_machine_net/services/network_service.dart';

class PastVuProvider implements DataProvider {
  final dio = Dio(
    BaseOptions(baseUrl: 'https://pastvu.com'),
  );
  String? userAgent;

  PastVuProvider({this.userAgent,}) {
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
          [
            [area.minLng, area.minLat],
            [area.maxLng, area.minLat],
            [area.maxLng, area.maxLat],
            [area.minLng, area.maxLat],
            [area.minLng, area.minLat],
          ]
        ],
      },
      if (startDate != null)
        'year': startDate.year,
      if (endDate != null)
        'year2': endDate.year,
      'isPainting': 0,
      if (zoom != null)
        'localWork': zoom >= 17 ? 1 : 0,
    };
    final userAgent = this.userAgent;
    final response = await dio.get('/api2',
      queryParameters: {
        'method': 'photo.getByBounds',
        'params': json.encode(params),
      },
      options: Options(
        headers: {
          if (userAgent != null)
            HttpHeaders.userAgentHeader: userAgent,
        },
      ),
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
      'isPainting': 0,
    };
    final userAgent = this.userAgent;
    final response = await dio.get('/api2',
      queryParameters: {
        'method': 'photo.giveNearestPhotos',
        'params': json.encode(params),
      },
      options: Options(
        headers: {
          if (userAgent != null)
            HttpHeaders.userAgentHeader: userAgent,
        },
      ),
    );
    return [
      for (final item in response.data['result']['photos'] as List)
        _decode(item),
    ];
  }

  Picture _decode(dynamic obj) {
    final baseUrl = dio.options.baseUrl;
    final id = obj['cid'].toString();
    final path = obj['file'].toString();
    final coord = obj['geo'] as List;
    return Picture(
      id: id,
      url: '$baseUrl/_p/a/$path',
      previewUrl: '$baseUrl/_p/h/$path',
      description: obj['title'] as String,
      latitude: coord[0] as double,
      longitude: coord[1] as double,
      bearing: _decodeOrientation(obj['dir']?.toString()),
      margin: '0,0,0,19',
      site: 'https://pastvu.com/p/$id',
      time: [
        obj['year']?.toString(),
        obj['year2']?.toString(),
      ].whereType<String>()
          .toSet()
          .sorted((x, y) => x.compareTo(y))
          .join('-'),
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
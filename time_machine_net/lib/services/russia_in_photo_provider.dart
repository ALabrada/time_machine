import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/domain/area.dart';

import 'network_service.dart';

class RussiaInPhotoProvider implements DataProvider {
  final dio = Dio(
      BaseOptions(baseUrl: 'https://russiainphoto.ru')
  );
  String? userAgent;

  RussiaInPhotoProvider({this.userAgent,}) {
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
    final userAgent = this.userAgent;
    final response = await dio.get('/rest/front/map-grid/',
      queryParameters: {
        'bounds': '${area.maxLat},${area.minLng},${area.minLat},${area.maxLng}',
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
        for (final _ in Iterable.generate(item['photos_count'] as int))
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
    throw Exception('Request not supported');
  }

  Picture _decode(dynamic obj) {
    return Picture(
      id: obj['photo']['id'].toString(),
      url: obj['photo']['url'].toString(),
      latitude: obj['lat'] as double,
      longitude: obj['lon'] as double,
    );
  }
}
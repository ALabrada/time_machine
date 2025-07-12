import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_math/flutter_geo_math.dart';
import 'package:latlong2/latlong.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/domain/area.dart';

import 'network_service.dart';

class RetroPhotosProvider implements DataProvider {
  final dio = Dio(
      BaseOptions(baseUrl: 'https://www.re.photos')
  );
  String? userAgent;

  RetroPhotosProvider({this.userAgent,}) {
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
    final response = await dio.get('/api/geo_template/',
      queryParameters: {
        'position_in': '${area.minLng}_${area.minLat}_${area.maxLng}_${area.maxLat}',
        if (startDate != null)
          'later_than': '${startDate.year}-${startDate.month}-${startDate.day}',
        if (endDate != null)
          'earlier_than': '${endDate.year}-${endDate.month}-${endDate.day}',
      },
      options: Options(
        headers: {
          if (userAgent != null)
            HttpHeaders.userAgentHeader: userAgent,
        },
      ),
    );
    return Stream.fromIterable(response.data['rest'] as List)
      .where((item) => item['position']['type'] == 'Point')
      .asyncMap(_download)
      .toList();
  }

  @override
  Future<List<Picture>> findNear({
    required Location location,
    required double radius,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final north = FlutterMapMath.destinationPoint(location.lat, location.lng, radius, 0.0);
    final east = FlutterMapMath.destinationPoint(location.lat, location.lng, radius, 90.0);
    final south = FlutterMapMath.destinationPoint(location.lat, location.lng, radius, 180.0);
    final west = FlutterMapMath.destinationPoint(location.lat, location.lng, radius, -90.0);
    assert(north.latitude >= south.latitude);
    assert(east.longitude >= west.longitude);
    final area = Area(
      minLat: south.latitude,
      minLng: west.longitude,
      maxLat: north.latitude,
      maxLng: east.longitude,
    );
    final isInBoundary = FlutterMapMath.createBoundary(LatLng(location.lat, location.lng), radius);
    final result = await findIn(area: area, startDate: startDate, endDate: endDate);
    result.removeWhere((e) => !isInBoundary(LatLng(e.latitude, e.longitude)));
    return result;
  }

  Future<List<Picture>> search({
    required String query,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final userAgent = this.userAgent;
    final response = await dio.get('/api/template/',
      queryParameters: {
        'search': query,
        'ordering': '-creation_time',
        if (startDate != null)
          'later_than': '${startDate.year}-${startDate.month}-${startDate.day}',
        if (endDate != null)
          'earlier_than': '${endDate.year}-${endDate.month}-${endDate.day}',
      },
      options: Options(
        headers: {
          if (userAgent != null)
            HttpHeaders.userAgentHeader: userAgent,
        },
      ),
    );
    return Stream.fromIterable(response.data['results'] as List)
        .where((item) => item['position']['type'] == 'Point')
        .asyncMap(_download)
        .toList();
  }

  Future<Picture> _download(dynamic obj) async {
    final userAgent = this.userAgent;
    final id = obj['id'].toString();
    final response = await dio.get('/api/template/$id/',
      options: Options(
        headers: {
          if (userAgent != null)
            HttpHeaders.userAgentHeader: userAgent,
        },
      ),
    );
    return _decode(obj, response.data);
  }

  Picture _decode(dynamic obj, dynamic details) {
    return Picture(
      id: obj['id'].toString(),
      description: details['title'],
      url: details['image']['file_fullscreen'].toString(),
      previewUrl: details['image']['file_thumb'].toString(),
      time: details['image']['creation_date'].toString(),
      site: '${dio.options.baseUrl}/en/template/${obj['id']}/',
      latitude: obj['position']['coordinates'][0] as double,
      longitude: obj['position']['coordinates'][1] as double,
    );
  }
}
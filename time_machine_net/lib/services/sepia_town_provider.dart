import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_math/flutter_geo_math.dart';
import 'package:latlong2/latlong.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/domain/area.dart';

import 'network_service.dart';

class SepiaTownProvider implements DataProvider {
  final dio = Dio(
      BaseOptions(baseUrl: 'https://www.sepiatown.com')
  );
  String? userAgent;

  SepiaTownProvider({this.userAgent,}) {
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
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final response = await dio.get('/service/artifacts/${area.maxLat}/${area.minLat}/${area.maxLng}/${area.minLng}/${area.zoom?.toInt() ?? 0}/0/$timestamp',
      options: Options(
        headers: {
          if (userAgent != null)
            HttpHeaders.userAgentHeader: userAgent,
          HttpHeaders.acceptHeader: 'application/json',
        },
      ),
    );
    return [
      for (final item in response.data as List)
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

  Future<Picture> get(String id) async {
    final userAgent = this.userAgent;
    final response = await dio.get('/service/artifact/$id',
      options: Options(
        headers: {
          if (userAgent != null)
            HttpHeaders.userAgentHeader: userAgent,
          HttpHeaders.acceptHeader: 'application/json',
        },
      ),
    );
    return _decode(response.data);
  }

  Picture _decode(dynamic obj) {
    final id = obj['artifact_id'].toString();
    final ext = obj['file_extension']?.toString() ?? 'jpg';
    final imgPath = obj['file_large_image_path']?.toString() ?? '/archives/images/large/${id}_large.$ext';
    final previewPath = obj['file_preview_image_path']?.toString() ?? '/archives/images/medium/${id}_medium.$ext';
    return Picture(
      id: id,
      description: obj['title'].toString(),
      url: '${dio.options.baseUrl}$imgPath',
      previewUrl: '${dio.options.baseUrl}$previewPath',
      site: '${dio.options.baseUrl}/$id',
      latitude: obj['latitude'] as double,
      longitude: obj['longitude'] as double,
      bearing: _decodeOrientation(obj['vantage']?.toString())
    );
  }

  double? _decodeOrientation(String? direction) {
    switch (direction) {
      case 'N': return 0;
      case 'NE': return 45;
      case 'E': return 90;
      case 'SE': return 135;
      case 'S': return 180;
      case 'SW': return 225;
      case 'W': return 270;
      case 'NW': return 315;
      default: return null;
    }
  }
}
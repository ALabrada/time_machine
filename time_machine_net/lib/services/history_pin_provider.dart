import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_math/flutter_geo_math.dart';
import 'package:latlong2/latlong.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/domain/area.dart';

import 'network_service.dart';

class HistoryPinProvider implements DataProvider {
  final dio = Dio(
      BaseOptions(baseUrl: 'https://www.historypin.org')
  );
  String? userAgent;

  HistoryPinProvider({this.userAgent,}) {
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
    final response = await dio.get('/en/api/explore/pin/get_gallery.json',
      queryParameters: {
        'bounds': '${area.minLat},${area.minLng},${area.maxLat},${area.maxLng}',
      },
      options: Options(
        headers: {
          if (userAgent != null)
            HttpHeaders.userAgentHeader: userAgent,
          HttpHeaders.acceptHeader: 'application/json',
        },
      ),
    );
    return [
      for (final item in response.data['results'] as List)
        if (item['node_type']?.toString() == 'pin' && item['type']?.toString() == 'photo')
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
    final response = await dio.get('/en/api/explore/pin/get.json',
      queryParameters: {
        'id': id,
      },
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
    final id = obj['id'].toString();
    final sitePath = obj['url']?.toString() ?? '/en/explore/pin/$id';
    final imgPath = obj['display']?['content']?.toString() ?? obj['image'].toString();
    return Picture(
      id: id,
      description: obj['caption'].toString(),
      time: obj['date'].toString(),
      url: '${dio.options.baseUrl}$imgPath',
      site: '${dio.options.baseUrl}$sitePath',
      latitude: obj['location']['lat'] as double,
      longitude: obj['location']['lng'] as double,
    );
  }
}
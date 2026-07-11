import 'dart:io';
import 'package:cachette/cachette.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map_math/flutter_geo_math.dart';
import 'package:latlong2/latlong.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/domain/area.dart';

import 'network_service.dart';

class RetroPhotosProvider implements DataProvider {
  final cache = Cachette<String, Picture>(1000);
  final dio = Dio(
      BaseOptions(baseUrl: 'https://www.re.photos')
  );
  String? userAgent;

  RetroPhotosProvider({this.userAgent,}) {
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
          'later_than': _format(startDate),
        if (endDate != null)
          'earlier_than': _format(endDate),
      },
      options: Options(
        headers: {
          if (userAgent != null)
            HttpHeaders.userAgentHeader: userAgent,
        },
      ),
    );
    return [
      for (final item in response.data['rest'])
        if (item['position']['type'] == 'Point')
          _decodeItem(item),
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
          'later_than': _format(startDate),
        if (endDate != null)
          'earlier_than': _format(endDate),
      },
      options: Options(
        headers: {
          if (userAgent != null)
            HttpHeaders.userAgentHeader: userAgent,
        },
      ),
    );
    return [
      for (final item in response.data['results'])
        if (item['position']['type'] == 'Point')
          _decodeItem(item),
    ];
  }

  @override
  Future<Picture> fetch(Picture original) async {
    final userAgent = this.userAgent;
    final id = original.id;
    final cached = cache[id];
    if (cached != null) {
      return cached;
    }
    final response = await dio.get('/api/template/$id/',
      options: Options(
        headers: {
          if (userAgent != null)
            HttpHeaders.userAgentHeader: userAgent,
        },
      ),
    );
    final item = _decodeDetails(details: response.data, original: original);
    cache[id] = item;
    return item;
  }

  String _format(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Picture _decodeDetails({required dynamic details, required Picture original}) {
    return Picture(
      id: original.id,
      description: details['title'],
      url: details['image']['file_fullscreen'].toString(),
      previewUrl: details['image']['file_thumb'].toString(),
      time: details['image']['creation_date'].toString(),
      site: original.site,
      latitude: original.latitude,
      longitude: original.longitude,
    );
  }

  Picture _decodeItem(dynamic obj) {
    final id = obj['id'].toString();

    final cached = cache[id];
    if (cached != null) {
      return cached;
    }

    return Picture(
      id: id,
      url: '',
      site: '${dio.options.baseUrl}/en/template/${obj['id']}/',
      latitude: obj['position']['coordinates'][1] as double,
      longitude: obj['position']['coordinates'][0] as double,
    );
  }
}
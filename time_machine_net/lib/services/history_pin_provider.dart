import 'dart:io';
import 'package:cachette/cachette.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map_math/flutter_geo_math.dart';
import 'package:html/parser.dart';
import 'package:latlong2/latlong.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/domain/area.dart';

import 'network_service.dart';

class HistoryPinProvider implements DataProvider {
  final cache = Cachette<String, Picture>(1000);
  final dio = Dio(
      BaseOptions(baseUrl: 'https://www.historypin.org')
  );
  String? userAgent;

  HistoryPinProvider({this.userAgent,}) {
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
    final response = await dio.get('/pins.json',
      queryParameters: {
        'nelat': area.maxLat,
        'nelng': area.maxLng,
        'swlat': area.minLat,
        'swlng': area.minLng,
        'page': 1,
        'page_size': 100,
        'primary_media_type': 'image',
        if (startDate != null)
          'start_date': '${startDate.year}-${startDate.month}-${startDate.day}',
        if (endDate != null)
          'end_date': '${endDate.year}-${endDate.month}-${endDate.day}'
      },
      options: Options(
        headers: {
          if (userAgent != null)
            HttpHeaders.userAgentHeader: userAgent,
          HttpHeaders.acceptHeader: 'application/json',
        },
      ),
    );
    return Stream.fromIterable(response.data['pins'] as List)
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

  Future<Picture> _download(dynamic obj) async {
    final userAgent = this.userAgent;
    final id = obj['id'].toString();
    final cached = cache[id];
    if (cached != null) {
      return cached;
    }
    final response = await dio.get('/pins/map',
      queryParameters: {
        'pin_card': id,
      },
      options: Options(
        headers: {
          if (userAgent != null)
            HttpHeaders.userAgentHeader: userAgent,
        },
      ),
    );
    final item = _decode(json: obj, html: response.data);
    cache[id] = item;
    return item;
  }

  Picture _decode({required dynamic html, required dynamic json}) {
    final id = json['id'].toString();
    final document = parse(html);
       
    final sitePath = document.getElementsByClassName('pin-card-link').firstOrNull?.attributes['href'] ?? '/pins/$id';
    final imgUrl = document.getElementsByClassName('pin-card-image').firstOrNull?.getElementsByTagName('img').firstOrNull?.attributes['src'];
    final title = document.getElementsByClassName('pin-card-title').firstOrNull?.text;
    final date = document.getElementsByClassName('pin-card-date').firstOrNull?.text;
    
    return Picture(
      id: id,
      description: title,
      time: date,
      url: imgUrl ?? '',
      site: '${dio.options.baseUrl}$sitePath',
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
    );
  }
}
import 'package:dio/dio.dart';

import 'package:time_machine_core/domain/area.dart';
import 'package:time_machine_core/domain/location.dart';
import 'package:time_machine_core/domain/picture.dart';
import '../geo_math.dart';
import '../network_service.dart';

class RussiaInPhotoProvider implements DataProvider {
  final dio = Dio(
    BaseOptions(baseUrl: 'https://russiainphoto.ru'),
  );
  String? userAgent;

  RussiaInPhotoProvider({this.userAgent, bool logRequests = false}) {
    if (logRequests) {
      dio.interceptors.add(
        LogInterceptor(
          request: true,
          requestBody: true,
          responseBody: true,
          error: true,
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
    final response = await dio.get('/rest/front/map-grid/',
      queryParameters: {
        'bounds': '${area.maxLat},${area.minLng},${area.minLat},${area.maxLng}',
      },
      options: Options(
        headers: {
          if (userAgent != null)
            userAgentHeader: userAgent,
        },
      ),
    );
    // Each grid cell reports a representative photo plus a photos_count of the
    // historical images at that location. There is no per-photo detail in this
    // endpoint, so one marker per cell is emitted — repeating the same photo id
    // (photos_count times) only produced duplicate markers that crash the map.
    return [
      for (final item in response.data['results'] as List)
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
    final area = areaAround(location: location, radius: radius);
    final result = await findIn(area: area, startDate: startDate, endDate: endDate);
    result.removeWhere((e) => !isWithinRadius(
      location: location,
      radius: radius,
      latitude: e.latitude,
      longitude: e.longitude,
    ));
    return result;
  }

  @override
  Future<Picture> fetch(Picture original) async => original;

  Picture _decode(dynamic obj) {
    final hash = obj['geohash']?.toString();
    return Picture(
      id: obj['photo']['id'].toString(),
      url: obj['photo']['url'].toString(),
      site: hash == null ? null : '${dio.options.baseUrl}/search/photo/?page=1&geohash=$hash&paginate_page=1&index=1',
      latitude: obj['lat'] as double,
      longitude: obj['lon'] as double,
    );
  }
}
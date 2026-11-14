import 'package:dio/dio.dart';
import 'package:time_machine_core/domain/area.dart';
import 'package:time_machine_core/domain/location.dart';
import 'package:time_machine_core/domain/picture.dart';
import 'package:time_machine_core/domain/place_info.dart';
import 'package:time_machine_sources/services/network_service.dart';

class ProxyNetworkService extends NetworkService {
  ProxyNetworkService({
    required String backendUrl,
    Map<String, GeocodingService> geocoders = const {},
    Map<String, DataProvider> providers = const {},
    String? userAgent,
    Dio? dio,
  }) : _backendUrl = backendUrl,
       _dio = dio ?? Dio(),
       super(
         geocoders: geocoders,
         providers: providers,
         userAgent: userAgent,
       );

  final String _backendUrl;
  final Dio _dio;

  @override
  Future<Picture?> fetchPicture(Picture picture) async {
    final response = await _dio.post(
      '$_backendUrl/api/fetchPicture',
      data: {'picture': picture.toJson()},
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );
    if (response.statusCode == 404 && response.data is! Map) {
      return null;
    }
    final data = response.data as Map<String, dynamic>;
    if (data['picture'] == null) {
      return null;
    }
    return Picture.fromJson(data['picture'] as Map<String, dynamic>);
  }

  @override
  Future<Map<String, List<Picture>>> findIn({
    required Area area,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? sources,
  }) async {
    final response = await _dio.post(
      '$_backendUrl/api/findIn',
      data: {
        'area': area.toJson(),
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
        if (sources != null) 'sources': sources,
      },
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );
    return _decodePictures(response.data as Map<String, dynamic>);
  }

  @override
  Future<Map<String, List<Picture>>> findNear({
    required Location location,
    required double radius,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? sources,
  }) async {
    final response = await _dio.post(
      '$_backendUrl/api/findNear',
      data: {
        'location': location.toJson(),
        'radius': radius,
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
        if (sources != null) 'sources': sources,
      },
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );
    return _decodePictures(response.data as Map<String, dynamic>);
  }

  @override
  Future<List<PlaceInfo>> searchAddress({
    required String query,
    String? source,
  }) async {
    final response = await _dio.post(
      '$_backendUrl/api/searchAddress',
      data: {
        'query': query,
        if (source != null) 'source': source,
      },
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );
    return _decodePlaces(response.data as List);
  }

  @override
  Future<List<PlaceInfo>> searchCoordinates({
    required Location coordinates,
    String? source,
  }) async {
    final response = await _dio.post(
      '$_backendUrl/api/searchCoordinates',
      data: {
        'location': coordinates.toJson(),
        if (source != null) 'source': source,
      },
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );
    return _decodePlaces(response.data as List);
  }

  Map<String, List<Picture>> _decodePictures(Map<String, dynamic> data) {
    return data.map((provider, items) => MapEntry(
      provider,
      [
        for (final item in items as List)
          Picture.fromJson(item as Map<String, dynamic>),
      ],
    ));
  }

  List<PlaceInfo> _decodePlaces(List data) {
    return [
      for (final item in data)
        PlaceInfo.fromJson(item as Map<String, dynamic>),
    ];
  }
}
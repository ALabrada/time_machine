import 'dart:io';

import 'package:dio/dio.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/domain/area.dart';
import 'package:time_machine_net/domain/place_info.dart';

class NetworkService {
  NetworkService({
    required this.geocoders,
    required this.providers,
    this.userAgent,
  });

  final Map<String, GeocodingService> geocoders;
  final Map<String, DataProvider> providers;
  String? userAgent;

  Future<void> download(
      String source,
      String target, {
        ProgressCallback? onReceiveProgress,
      }) async {
    final userAgent = this.userAgent;
    await Dio().download(source, target,
      onReceiveProgress: onReceiveProgress,
      options: Options(headers: {
        if (userAgent != null)
          HttpHeaders.userAgentHeader: userAgent,
      })
    );
  }

  Future<Map<String, List<Picture>>> findIn({
    required Area area,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? sources,
  }) async {
    final operations = providers.entries
        .where((e) => sources?.contains(e.key) ?? true)
        .map((entry) async {
          try {
            final result = await entry.value.findIn(
              area: area,
              startDate: startDate,
              endDate: endDate,
            );
            for (final item in result) {
              item.provider = entry.key;
            }
            return (entry.key, result, null);
          } catch (error) {
            return (entry.key, null, error);
          }
        });
    final results = await Future.wait(operations);
    return {
      for (final result in results)
        if (result.$2 != null)
          result.$1: result.$2!
    };
  }

  Future<Map<String, List<Picture>>> findNear({
    required Location location,
    required double radius,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? sources,
  }) async {
    final operations = providers.entries
        .where((e) => sources?.contains(e.key) ?? true)
        .map((entry) async {
      try {
        final result = await entry.value.findNear(
          location: location,
          radius: radius,
          startDate: startDate,
          endDate: endDate,
        );
        for (final item in result) {
          item.provider = entry.key;
        }
        return (entry.key, result, null);
      } catch (error) {
        return (entry.key, null, error);
      }
    });
    final results = await Future.wait(operations);
    return {
      for (final result in results)
        if (result.$2 != null)
          result.$1: result.$2!
    };
  }

  Future<List<PlaceInfo>> searchAddress({
    required String query,
    String? source,
  }) async {
    final searchEngine = source == null ? geocoders.values.firstOrNull : geocoders[source];
    if (searchEngine == null) {
      throw Exception("Invalid source");
    }
    return await searchEngine.searchAddress(query);
  }

  Future<List<PlaceInfo>> searchCoordinates({
    required Location coordinates,
    String? source,
  }) async {
    final searchEngine = source == null ? geocoders.values.firstOrNull : geocoders[source];
    if (searchEngine == null) {
      throw Exception("Invalid source");
    }
    return await searchEngine.searchCoordinates(coordinates);
  }
}

abstract class DataProvider {
  Future<List<Picture>> findIn({
    required Area area,
    DateTime? startDate,
    DateTime? endDate,
  });

  Future<List<Picture>> findNear({
    required Location location,
    required double radius,
    DateTime? startDate,
    DateTime? endDate,
  });
}

abstract class GeocodingService {
  Future<List<PlaceInfo>> searchAddress(String query);
  Future<List<PlaceInfo>> searchCoordinates(Location location);
}
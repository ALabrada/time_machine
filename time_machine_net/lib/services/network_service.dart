import 'package:dio/dio.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/domain/area.dart';

class NetworkService {
  NetworkService({required this.providers});
  
  final Map<String, DataProvider> providers;

  Future<void> download(
      String source,
      String target, {
        ProgressCallback? onReceiveProgress,
      }) async {
    await Dio().download(source, target, onReceiveProgress: onReceiveProgress);
  }

  Future<Map<String, List<Picture>>> findIn({
    required Area area,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final operations = providers.entries
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
  }) async {
    final operations = providers.entries
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
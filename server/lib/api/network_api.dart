import 'package:shelf/shelf.dart';
import 'package:time_machine_core/domain/area.dart';
import 'package:time_machine_core/domain/location.dart';
import 'package:time_machine_core/domain/picture.dart';
import 'package:time_machine_sources/services/network_service.dart';

import 'api_utils.dart';

/// Handles the provider and geocoder proxy endpoints.
class NetworkApi {
  NetworkApi({required this.networkService, required this.maxBodyBytes});

  final NetworkService networkService;
  final int maxBodyBytes;

  Future<Response> findIn(Request request) async {
    final body = decodeJsonBody(await readBody(request, maxBodyBytes));
    final area = Area.fromJson(body['area'] as Map<String, dynamic>);
    final result = await networkService.findIn(
      area: area,
      startDate: parseDate(body['startDate']),
      endDate: parseDate(body['endDate']),
      sources: _sources(body),
    );
    return okResponse({
      for (final entry in result.entries)
        entry.key: [for (final picture in entry.value) picture.toJson()],
    });
  }

  Future<Response> findNear(Request request) async {
    final body = decodeJsonBody(await readBody(request, maxBodyBytes));
    final location = Location.fromJson(
      body['location'] as Map<String, dynamic>,
    );
    final radius = (body['radius'] as num).toDouble();
    final result = await networkService.findNear(
      location: location,
      radius: radius,
      startDate: parseDate(body['startDate']),
      endDate: parseDate(body['endDate']),
      sources: _sources(body),
    );
    return okResponse({
      for (final entry in result.entries)
        entry.key: [for (final picture in entry.value) picture.toJson()],
    });
  }

  Future<Response> fetchPicture(Request request) async {
    final body = decodeJsonBody(await readBody(request, maxBodyBytes));
    final picture = Picture.fromJson(body['picture'] as Map<String, dynamic>);
    final result = await networkService.fetchPicture(picture);
    if (result == null) {
      return jsonError(404, 'picture not found');
    }
    return okResponse({'picture': result.toJson()});
  }

  Future<Response> searchAddress(Request request) async {
    final body = decodeJsonBody(await readBody(request, maxBodyBytes));
    final result = await networkService.searchAddress(
      query: body['query'] as String,
      source: body['source'] as String?,
    );
    return okResponse([for (final place in result) place.toJson()]);
  }

  Future<Response> searchCoordinates(Request request) async {
    final body = decodeJsonBody(await readBody(request, maxBodyBytes));
    final location = Location.fromJson(
      body['location'] as Map<String, dynamic>,
    );
    final result = await networkService.searchCoordinates(
      coordinates: location,
      source: body['source'] as String?,
    );
    return okResponse([for (final place in result) place.toJson()]);
  }

  List<String>? _sources(Map<String, dynamic> body) {
    final sources = body['sources'];
    return sources == null ? null : (sources as List).cast<String>();
  }
}

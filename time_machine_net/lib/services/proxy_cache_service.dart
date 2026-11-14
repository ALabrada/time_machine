import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:time_machine_net/services/cache_service.dart';

/// Web-only [CacheService] that routes remote image URIs through the proxy
/// backend's `/api/image` endpoint: the browser cannot fetch provider images
/// directly (CORS), so the backend downloads and caches them instead. Local
/// `file:`/`data:` URIs are handled by the base service untouched.
class ProxyCacheService extends CacheService {
  ProxyCacheService({
    required String backendUrl,
    String? userAgent,
    BaseCacheManager? cacheManager,
  }) : _backendUrl = backendUrl,
       _userAgent = userAgent,
       super(cacheManager: cacheManager);

  final String _backendUrl;
  final String? _userAgent;
  final Dio _dio = Dio();

  @override
  ImageProvider imageProvider(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && (uri.isScheme('file') || uri.isScheme('data'))) {
      return super.imageProvider(url);
    }
    return CachedNetworkImageProvider(
      Uri.parse('$_backendUrl/api/image')
          .replace(queryParameters: {'url': url})
          .toString(),
      cacheManager: cacheManager,
    );
  }

  @override
  Future<XFile> fetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && (uri.isScheme('data') || uri.isScheme('file'))) {
      return super.fetch(url);
    }
    final response = await _dio.getUri<List<int>>(
      Uri.parse('$_backendUrl/api/image').replace(
        queryParameters: {
          'url': url,
          if (uri != null && uri.queryParameters['provider'] != null)
            'provider': uri.queryParameters['provider'],
        },
      ),
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          if (_userAgent != null) 'user-agent': _userAgent,
        },
      ),
    );
    if (response.data == null) {
      throw HttpExceptionWithStatus(response.statusCode ?? 500, response.statusMessage ?? '?');
    }
    return XFile.fromData(Uint8List.fromList(response.data!),
      mimeType: response.headers.value(Headers.contentTypeHeader) ?? 'application/octet-stream',
      name: uri != null && uri.queryParameters['provider'] != null
          ? 'photo.${uri.queryParameters['provider']}'
          : 'photo',
    );
  }
}
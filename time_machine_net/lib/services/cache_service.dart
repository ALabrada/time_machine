import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

final class CacheService {
  CacheService({
    BaseCacheManager? cacheManager,
  }) : cacheManager = cacheManager ?? DefaultCacheManager();

  CacheService.defaultInstance() : this(cacheManager: null);

  final BaseCacheManager cacheManager;

  Future<XFile> fetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.isScheme('data')) {
      final data = UriData.parse(url);
      return XFile.fromData(data.contentAsBytes(),
        mimeType: data.mimeType,
        name: 'photo.${data.mimeType.split('/').last}',
      );
    }
    if (uri != null && uri.isScheme('file')) {
      return XFile(uri.path);
    }
    if (kIsWeb && uri != null) {
      final response = await Dio().getUri<List<int>>(uri,
        options: Options(responseType: ResponseType.bytes)
      );
      if (response.data == null) {
        throw HttpExceptionWithStatus(response.statusCode ?? 500, response.statusMessage ?? '?');
      }
      return XFile.fromData(Uint8List.fromList(response.data!),
        mimeType: response.headers.value(Headers.contentTypeHeader),
        name: uri.pathSegments.lastOrNull,
      );
    }
    final file = await cacheManager.getSingleFile(url);
    return XFile(file.path);
  }
}
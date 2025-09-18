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
    if (url.startsWith('data:')) {
      final data = UriData.parse(url);
      return XFile.fromData(data.contentAsBytes());
    }
    if (kIsWeb) {
      final response = await Dio().get<List<int>>(url,
        options: Options(responseType: ResponseType.bytes)
      );
      if (response.data == null) {
        throw HttpExceptionWithStatus(response.statusCode ?? 500, response.statusMessage ?? '?');
      }
      return XFile.fromData(Uint8List.fromList(response.data!),
        mimeType: response.headers.value(Headers.contentTypeHeader),
      );
    }
    final file = await cacheManager.getSingleFile(url);
    return XFile(file.path);
  }
}
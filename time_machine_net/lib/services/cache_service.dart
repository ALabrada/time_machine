import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class CacheService {
  CacheService({
    BaseCacheManager? cacheManager,
    this.pathExpander,
  }) : _cacheManager = cacheManager;

  CacheService.defaultInstance() : this(cacheManager: null);

  final BaseCacheManager? _cacheManager;
  late BaseCacheManager cacheManager =
      _cacheManager ?? CachedNetworkImageProvider.defaultCacheManager;

  /// Resolves a local `file:` `[FILES]` placeholder path to the app's file
  /// directory when browsing locally stored pictures.
  final String Function(String path)? pathExpander;

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
      final path = pathExpander?.call(uri.path) ?? uri.path;
      return XFile(path);
    }
    final file = await cacheManager.getSingleFile(url);
    return XFile(file.path);
  }

  /// Builds the [ImageProvider] used to display [url].
  ///
  /// * `file:` -> [FileImage] with the path expanded through [pathExpander];
  /// * `data:` -> [MemoryImage];
  /// * remote -> [CachedNetworkImageProvider] fetched directly and cached on
  ///   disk by [cacheManager].
  ImageProvider imageProvider(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.isScheme('file')) {
      final path = pathExpander?.call(uri.path) ?? uri.path;
      return FileImage(File(path));
    }
    if (uri != null && uri.isScheme('data')) {
      return MemoryImage(UriData.fromUri(uri).contentAsBytes());
    }
    return CachedNetworkImageProvider(url, cacheManager: cacheManager);
  }
}
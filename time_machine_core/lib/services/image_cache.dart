import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cachette/cachette.dart';
import 'package:dio/dio.dart';
import 'package:time_machine_core/domain/picture.dart';

/// A cached image response.
class CachedImage {
  final List<int> bytes;
  final String? contentType;
  const CachedImage({required this.bytes, this.contentType});
}

/// Resolved image bytes ready to be uploaded or stored.
class ResolvedImage {
  const ResolvedImage({required this.bytes, this.mimeType});

  final Uint8List bytes;
  final String? mimeType;
}

/// Resolves the actual bytes of a [Picture].
///
/// The app resolves local files/disk cache through its `CacheService`, while
/// the proxy backend uses [CachedImageFetcher], which downloads remote URLs and
/// decodes inline `data:` URLs.
abstract interface class ImageResolver {
  Future<ResolvedImage?> resolve(Picture picture);
}

/// Memory/disk cache for remote images.
///
/// The proxy backend also uses it as its [ImageResolver]: [resolve] downloads
/// HTTP(S) images through the cache and decodes inline `data:` URLs. Local
/// `file:` URLs are not accessible to the server and are ignored.
class CachedImageFetcher implements ImageResolver {
  final Dio dio;
  final Cachette<String, CachedImage> _memory;
  final Directory? diskDir;
  final int maxDiskSizeBytes;
  final Set<String> allowedHosts;

  CachedImageFetcher({
    Dio? dio,
    int memoryLimit = 5000,
    this.diskDir,
    this.maxDiskSizeBytes = 512 * 1024 * 1024,
    List<String> allowedHosts = const [],
  }) : dio = dio ?? Dio(),
       _memory = Cachette<String, CachedImage>(memoryLimit),
       allowedHosts = Set.of(allowedHosts);

  String _key(String url) => base64Url.encode(utf8.encode(url));

  String? _diskPath(String key) {
    final dir = diskDir;
    if (dir == null) {
      return null;
    }
    return '${dir.path}${Platform.pathSeparator}$key';
  }

  Future<CachedImage?> fetch(String url) async {
    final key = _key(url);
    final memory = _memory[key];
    if (memory != null) {
      return memory;
    }

    final diskPath = _diskPath(key);
    if (diskPath != null) {
      final file = File(diskPath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final image = CachedImage(bytes: bytes);
        _memory[key] = image;
        return image;
      }
    }

    // The host allow-list is always enforced for remote URLs. When no hosts
    // are configured the fetcher fails closed: it refuses every remote URL
    // rather than silently allowing arbitrary hosts.
    final host = Uri.tryParse(url)?.host;
    if (host == null || host.isEmpty || !allowedHosts.contains(host)) {
      throw StateError('Host "$host" is not allowed');
    }

    final response = await dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        // Never follow redirects: the host allow-list check above only covers
        // the initial URL, and following a redirect to a non-allow-listed (or
        // internal) host would turn this proxy into an SSRF vector.
        followRedirects: false,
      ),
    );
    final image = CachedImage(
      bytes: response.data ?? const [],
      contentType: response.headers.value('content-type'),
    );
    _memory[key] = image;
    if (diskPath != null) {
      await _writeDisk(key, diskPath, image.bytes);
    }
    return image;
  }

  @override
  Future<ResolvedImage?> resolve(Picture picture) async {
    final uri = Uri.tryParse(picture.url);
    if (uri == null) {
      return null;
    }
    if (uri.isScheme('data')) {
      final data = UriData.fromUri(uri);
      final bytes = data.contentAsBytes();
      if (bytes.isEmpty) {
        return null;
      }
      return ResolvedImage(
        bytes: bytes,
        mimeType: data.mimeType.isEmpty ? null : data.mimeType,
      );
    }
    if (uri.isScheme('http') || uri.isScheme('https')) {
      final image = await fetch(picture.url);
      if (image == null || image.bytes.isEmpty) {
        return null;
      }
      return ResolvedImage(
        bytes: Uint8List.fromList(image.bytes),
        mimeType: image.contentType,
      );
    }
    return null;
  }

  Future<void> _writeDisk(String key, String diskPath, List<int> bytes) async {
    final dir = diskDir;
    if (dir == null) {
      return;
    }
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await File(diskPath).writeAsBytes(bytes);
      await _cleanupOld(key);
    } catch (_) {
      // Disk cache is best-effort.
    }
  }

  Future<void> _cleanupOld(String newestKey) async {
    final dir = diskDir;
    if (dir == null || maxDiskSizeBytes <= 0) {
      return;
    }
    try {
      var total = 0;
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File) {
          final size = await entity.length();
          total += size;
          files.add(entity);
        }
      }
      if (total <= maxDiskSizeBytes) {
        return;
      }
      files.sort((a, b) => a.path == newestKey
          ? -1
          : b.path == newestKey ? 1 : 0);
      for (final file in files.skip(1)) {
        if (total <= maxDiskSizeBytes) {
          break;
        }
        final size = await file.length();
        await file.delete();
        total -= size;
      }
    } catch (_) {
      // Best-effort cleanup.
    }
  }
}

import 'dart:typed_data';

import 'package:time_machine_core/domain/picture.dart';

import 'image_cache.dart';

/// A picture ready to be uploaded to Telegram.
class TelegramPhoto {
  const TelegramPhoto({required this.bytes, this.mimeType});

  final Uint8List bytes;
  final String? mimeType;
}

/// Resolves the actual bytes of a [Picture].
///
/// The app resolves local files/disk cache through its [CacheService], while
/// the proxy backend downloads remote URLs and decodes inline `data:` URLs.
abstract interface class TelegramPhotoResolver {
  Future<TelegramPhoto?> resolve(Picture picture);
}

/// Resolves pictures from HTTP(S) URLs or inline `data:` URLs.
///
/// This is the resolver used by the proxy backend. Local `file:` URLs are not
/// accessible to the server and are ignored.
class NetworkTelegramPhotoResolver implements TelegramPhotoResolver {
  NetworkTelegramPhotoResolver({CachedImageFetcher? imageFetcher})
    : _imageFetcher = imageFetcher ?? CachedImageFetcher();

  final CachedImageFetcher _imageFetcher;

  @override
  Future<TelegramPhoto?> resolve(Picture picture) async {
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
      return TelegramPhoto(
        bytes: bytes,
        mimeType: data.mimeType.isEmpty ? null : data.mimeType,
      );
    }
    if (uri.isScheme('http') || uri.isScheme('https')) {
      final image = await _imageFetcher.fetch(picture.url);
      if (image == null || image.bytes.isEmpty) {
        return null;
      }
      return TelegramPhoto(
        bytes: Uint8List.fromList(image.bytes),
        mimeType: image.contentType,
      );
    }
    return null;
  }
}

import 'package:time_machine_net/time_machine_net.dart';

/// Resolves Telegram photos through the app's [CacheService].
///
/// Remote pictures come from the disk cache, while camera pictures on the web
/// are inline `data:` URLs and local pictures are expanded through the cache's
/// path expander.
class AppTelegramPhotoResolver implements TelegramPhotoResolver {
  AppTelegramPhotoResolver({required this.cacheService});

  final CacheService cacheService;

  @override
  Future<TelegramPhoto?> resolve(Picture picture) async {
    final file = await cacheService.fetch(picture.url);
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      return null;
    }
    return TelegramPhoto(bytes: bytes, mimeType: file.mimeType);
  }
}

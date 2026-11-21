import 'package:dio/dio.dart';
import 'package:time_machine_net/time_machine_net.dart';

/// Web-only [TelegramService] that delegates publishing to the proxy backend.
///
/// The bot token and channel id stay on the server; the browser only sends the
/// picture metadata and caption to `/api/telegram/submit`. The backend then
/// downloads (or decodes inline `data:` URLs) and submits the post to Telegram
/// for channel admin review.
class ProxyTelegramService extends TelegramService {
  ProxyTelegramService({
    required String backendUrl,
    Dio? dio,
  })  : _backendUrl = backendUrl,
        _dio = dio ??
            Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));

  final String _backendUrl;
  final Dio _dio;

  @override
  Future<bool> submit({
    required List<Picture> pictures,
    String? caption,
  }) async {
    if (pictures.isEmpty) {
      return false;
    }
    try {
      final response = await _dio.post(
        '$_backendUrl/api/telegram/submit',
        data: {
          'pictures': [for (final picture in pictures) picture.toJson()],
          if (caption != null) 'caption': caption,
        },
        options: Options(
          contentType: Headers.jsonContentType,
          responseType: ResponseType.json,
        ),
      );
      final data = response.data;
      if (data is Map) {
        return data['submitted'] == true;
      }
    } catch (_) {
      // The controller treats a failed submission as "nothing happened".
    }
    return false;
  }
}

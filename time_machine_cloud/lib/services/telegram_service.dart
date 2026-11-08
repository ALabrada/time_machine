import 'package:televerse/telegram.dart';
import 'package:televerse/televerse.dart';
import 'package:time_machine_core/domain/picture.dart';

import 'telegram_photo_resolver.dart';

/// Interface used by the proxy backend so tests/deployments can substitute a
/// different publisher.
abstract interface class TelegramPublisher {
  /// Whether a bot token and channel id are configured.
  bool get enabled;

  /// Submits a suggestion to the channel, pending admin approval.
  Future<bool> submit({
    required List<Picture> pictures,
    String? caption,
  });
}

/// Submits pictures to a Telegram channel through the televerse bot API.
///
/// The post is submitted as a Telegram suggested post, so the channel admin
/// must approve it before it becomes visible. The same implementation runs
/// natively in the app and in the server; only the [TelegramPhotoResolver]
/// differs.
class TelegramService implements TelegramPublisher {
  const TelegramService({
    this.apiKey,
    this.channelId,
    this.photoResolver,
  });

  final String? apiKey;
  final int? channelId;

  /// Loads picture bytes for the current platform.
  final TelegramPhotoResolver? photoResolver;

  @override
  bool get enabled =>
      (apiKey?.isNotEmpty ?? false) && channelId != null;

  @override
  Future<bool> submit({
    required List<Picture> pictures,
    String? caption,
  }) async {
    final apiKey = this.apiKey;
    final channelId = this.channelId;
    final resolver = photoResolver;
    if (pictures.isEmpty ||
        apiKey == null ||
        channelId == null ||
        resolver == null) {
      return false;
    }

    final photos = <TelegramPhoto>[];
    for (final picture in pictures) {
      final photo = await resolver.resolve(picture);
      if (photo != null) {
        photos.add(photo);
      }
    }
    if (photos.isEmpty) {
      return false;
    }

    final captionBlock = caption == null || caption.isEmpty
        ? null
        : RichBlockCaption(text: RichText.plain(text: caption));
    final photoBlocks = [
      for (final photo in photos)
        InputRichBlock.photo(
          photo: InputMediaPhoto(
            media: InputFile.fromBytes(
              photo.bytes,
              name: _photoName(photo.mimeType),
              mimeType: photo.mimeType,
            ),
          ),
        ),
    ];

    final blocks = <InputRichBlock>[];
    if (photoBlocks.length == 1) {
      final single = photoBlocks.single as InputRichBlockPhoto;
      blocks.add(InputRichBlock.photo(
        photo: single.photo,
        caption: captionBlock,
      ));
    } else {
      blocks.add(InputRichBlock.collage(
        blocks: photoBlocks,
        caption: captionBlock,
      ));
    }

    final last = pictures.last;
    if (last.latitude.isFinite && last.longitude.isFinite) {
      blocks.add(InputRichBlock.map(
        location: Location(
          latitude: last.latitude,
          longitude: last.longitude,
        ),
        zoom: 16,
        width: 800,
        height: 400,
      ));
    }

    final bot = Bot(apiKey);
    await bot.api.sendRichMessage(
      ChatID(channelId),
      InputRichMessage(blocks: blocks),
      suggestedPostParameters: const SuggestedPostParameters(),
    );
    return true;
  }

  String _photoName(String? contentType) {
    final extension = switch (contentType?.toLowerCase()) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      'image/heic' || 'image/heif' => 'heic',
      _ => 'jpg',
    };
    return 'photo.$extension';
  }
}

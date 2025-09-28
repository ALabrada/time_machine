import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:rxdart/rxdart.dart';
import 'package:televerse/telegram.dart';
import 'package:televerse/televerse.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/time_machine_net.dart';

final class TelegramService {
  const TelegramService({
    required this.apiKey,
    required this.channelId,
    this.channelName,
  });

  final String apiKey;
  final int channelId;
  final String? channelName;

  Future<bool> publish({
    required List<Picture> pictures,
    String? caption,
    required CacheService cacheService,
    DatabaseService? databaseService,
  }) async {
    if (pictures.isEmpty) {
      return false;
    }

    final files = await Stream.fromIterable(pictures)
      .asyncMap((p) => _openFile(
        picture: p,
        cacheService: cacheService,
        databaseService: databaseService,
      ))
      .whereNotNull()
      .toList();

    final bot = Bot(apiKey);
    final chatId = ChatID(channelId);

    final messages = await bot.api.sendMediaGroup(chatId, [
      for (final (index, file) in files.indexed)
        InputMedia.photo(
          media: file,
          caption: index == 0 ? caption : null,
        ),
    ]);

    if (messages.isEmpty) {
      return false;
    }

    await bot.api.sendLocation(chatId,pictures.last.latitude, pictures.last.longitude,
      replyParameters: ReplyParameters(messageId: messages.last.messageId),
    );

    return true;
  }

  Future<InputFile?> _openFile({
    Picture? picture,
    required CacheService cacheService,
    DatabaseService? databaseService,
  }) async {
    final url = picture == null ? null : Uri.tryParse(picture.url);
    if (url == null) {
      return null;
    }
    if (url.isScheme('file')) {
      final path = databaseService?.expandPath(url.path) ?? url.path;
      return InputFile.fromFile(io.File(path));
    }
    final file = await cacheService.fetch(url.toString());
    return kIsWeb || url.isScheme('data')
        ? InputFile.fromBytes(await file.readAsBytes())
        : InputFile.fromFile(io.File(file.path));
  }
}
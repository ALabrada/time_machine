import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:image_compare_2/image_compare_2.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_img/services/database_service.dart';
import 'package:time_machine_img/services/telegram_service.dart';
import 'package:time_machine_net/time_machine_net.dart';
import 'package:time_machine_res/time_machine_res.dart';
import 'package:url_launcher/url_launcher.dart';

class ComparisonController with TaskManager {
  ComparisonController({
    this.cacheManager,
    this.databaseService,
    this.networkService,
    this.telegramService,
    this.record,
  });

  final BaseCacheManager? cacheManager;
  final DatabaseService? databaseService;
  final NetworkService? networkService;
  final TelegramService? telegramService;
  Record? record;
  double? similarity;

  Future<Record?> loadRecord(int? id) async {
    if (id == null) {
      return null;
    }
    final record = await databaseService?.createRepository<Record>().getById(id);
    if (record == null) {
      return null;
    }

    this.record = record;
    record.picture = await databaseService?.createRepository<Picture>().getById(record.pictureId);

    final originalId = record.originalId;
    if (originalId != null) {
      record.original = await databaseService?.createRepository<Picture>().getById(originalId);
    }

    return record;
  }

  Future<bool> removeRecord() async {
    final record = this.record;
    final recordId = record?.localId;
    final db = databaseService;
    if (record == null || recordId == null || db == null) {
      return false;
    }

    if (!await db.createRepository<Record>().delete(recordId)) {
      return false;
    }

    if (!await db.createRepository<Picture>().delete(record.pictureId)) {
      return false;
    }

    final url = Uri.tryParse(record.picture?.url ?? '');
    if (url != null) {
      await File(url.path).delete();
    }

    return true;
  }

  Future<void> exportRecord() async {
    final record = this.record;
    final databaseService = this.databaseService;
    final id = record?.localId;
    if (record == null || id == null || databaseService == null) {
      return;
    }
    final data = await execute(() => databaseService.export(record: record));
    if (data == null) {
      return;
    }
    await FilePicker.platform.saveFile(
      dialogTitle: "Exporting pictures",
      fileName: 'hl_$id',
      bytes: data,
    );
  }

  Future<bool> publishToTelegram() async {
    final record = this.record;
    final original = record?.original;
    final picture = record?.picture;
    final telegramService = this.telegramService;
    if (record == null || original == null || picture == null || telegramService == null) {
      return false;
    }

    final caption = [
      if (original.description != null)
        original.description!,
      '${original.time ?? '?'} <--> ${picture.time ?? '?'}',
      if (original.site != null)
        original.site!,
    ].join('\n');

    await execute(() => telegramService.publish(
      pictures: [original, picture],
      caption: caption,
      cacheManager: cacheManager,
    ));
    return true;
  }

  Future<void> sharePictures() async {
    final record = this.record;
    final picture = record?.picture;
    final original = record?.original;
    final cache = cacheManager ?? DefaultCacheManager();
    if (record == null || picture == null) {
      return;
    }
    final originalFile = original == null
        ? null
        : await execute(() => cache.getSingleFile(original.url));
    await Share.shareXFiles([
      XFile(Uri.parse(picture.url).path),
      if (originalFile != null)
        XFile(originalFile.path),
    ], text: picture.description);
  }

  Future<double?> comparePictures(Record? record) async {
    if (similarity != null) {
      return similarity;
    }

    final picture = record?.picture;
    final original = record?.original;
    final cache = cacheManager ?? DefaultCacheManager();
    if (record == null || picture == null || original == null) {
      return null;
    }

    final originalViewPort = Record.tryParseViewPort(record.originalViewPort);
    final pictureViewPort = Record.tryParseViewPort(record.pictureViewPort);
    final intersection = originalViewPort == null || pictureViewPort == null
        ? null
        : originalViewPort.intersection(pictureViewPort);

    final originalFile = await cache.getSingleFile(original.url);
    var originalImage = await img.decodeImageFile(originalFile.path);
    if (originalImage == null) {
      return null;
    }
    if (intersection != null && originalViewPort != null) {
      final rect = cropImage(
        width: originalImage.width,
        height: originalImage.height,
        viewPort: originalViewPort,
        intersection: intersection,
      );
      originalImage = await Future.microtask(() => img.copyCrop(originalImage!,
        x: rect.left,
        y: rect.top,
        width: rect.width,
        height: rect.height,
      ));
    }

    final uri = Uri.tryParse(picture.url);
    var ownImage = uri != null && uri.scheme == 'file' ? await img.decodeImageFile(uri.path) : null;
    if (ownImage == null) {
      return null;
    }
    if (intersection != null && pictureViewPort != null) {
      final rect = cropImage(
        width: ownImage.width,
        height: ownImage.height,
        viewPort: pictureViewPort,
        intersection: intersection,
      );
      ownImage = await Future.microtask(() => img.copyCrop(ownImage!,
        x: rect.left,
        y: rect.top,
        width: rect.width,
        height: rect.height,
      ));
    }

    similarity = 1.0 - await compareImages(
      src1: originalImage,
      src2: ownImage,
      algorithm: MedianHash(),
    );
    return similarity;
  }
}
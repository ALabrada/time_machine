import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_img/controllers/sync_record_controller.dart';
import 'package:time_machine_img/services/database_service.dart';
import 'package:time_machine_img/services/similarity_service.dart';
import 'package:time_machine_img/services/telegram_service.dart';
import 'package:time_machine_net/time_machine_net.dart';
import 'package:time_machine_res/time_machine_res.dart';

class ComparisonController with TaskManager, SyncRecordController {
  ComparisonController({
    required this.cacheService,
    this.databaseService,
    this.networkService,
    this.telegramService,
    this.cloudSyncService,
    this.userMessages,
  });

  final CacheService cacheService;
  final DatabaseService? databaseService;
  final NetworkService? networkService;
  final TelegramService? telegramService;
  final CloudSyncService? cloudSyncService;
  final UserMessageService? userMessages;

  /// The similarity of the record currently being watched, republished whenever
  /// it changes so the page can rebuild from a stream instead of building a
  /// fresh [Future] on every frame.
  final similarityChanges = StreamController<double?>.broadcast();

  double? _similarity;

  /// The last computed similarity, or `null` if the record could not be
  /// compared (or has not been compared yet).
  double? get similarity => _similarity;

  int? _similarityRecordId;
  Future<double?>? _pendingComparison;

  /// Whether the Share-to-Telegram option is available (a Telegram bot token
  /// was configured at build time).
  bool get isTelegramSupported => telegramService != null;

  void watchRecord(int? id) {
    // A different record invalidates whatever was computed for the previous
    // one; without this a late-arriving result could be attributed to the
    // wrong picture.
    if (_similarityRecordId != id) {
      _similarityRecordId = id;
      _similarity = null;
      _pendingComparison = null;
      if (!similarityChanges.isClosed) {
        similarityChanges.add(null);
      }
    }
    watchSyncRecord(
      cloudSyncService: cloudSyncService,
      databaseService: databaseService,
      entityId: id,
    );
  }

  @override
  void dispose() {
    disposeSyncRecord();
    similarityChanges.close();
    super.dispose();
  }

  Future<bool> removeRecord() async {
    final record = this.record;
    final db = databaseService;
    return record != null && db != null && await db.removeRecord(record);
  }

  Future<void> exportRecord({String? dialogTitle}) async {
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
      dialogTitle: dialogTitle,
      fileName: 'export.zip',
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
      cacheService: cacheService,
      databaseService: databaseService,
    ));
    return true;
  }

  Future<void> savePictures({String? dialogTitle}) async {
    final record = this.record;
    final picture = record?.picture;
    final original = record?.original;
    if (record == null || picture == null) {
      return;
    }
    final pictureFile = await cacheService.fetch(picture.url);
    final originalFile = original == null
        ? null
        : await execute(() => cacheService.fetch(original.url));
    final result = await saveFiles(
      files: [
        pictureFile,
        if (originalFile != null)
          originalFile,
      ],
      text: picture.description,
      dialogTitle: dialogTitle,
    );
    if (result is FileSaved) {
      userMessages?.savedToFile(result.path);
    }
  }

  /// The similarity of [record]'s picture against its original.
  ///
  /// The work itself is off the UI isolate on every platform — an
  /// [Isolate.run] on native, the browser's own decoder and rasterizer on the
  /// web — so the returned [Future] can be awaited freely; the only main-thread
  /// cost is handing over two byte buffers.
  ///
  /// The future is memoized per record, so calling this from `build` is safe
  /// and does not restart the computation. Results are published on
  /// [similarityChanges].
  Future<double?> comparePictures(Record? record) {
    if (record == null || record != this.record) {
      return Future.value(_similarity);
    }
    if (_similarityRecordId != record.localId) {
      watchRecord(record.localId);
    }
    return _pendingComparison ??= _comparePictures(record);
  }

  Future<double?> _comparePictures(Record record) async {
    try {
      final picture = record.picture;
      final original = record.original;
      if (picture == null || original == null) {
        return _publish(null);
      }

      // Read the bytes here, on the UI isolate: this is I/O, and it yields.
      // Everything after it is either a background isolate or a browser
      // decoder, so no full-resolution image is decoded on the UI isolate.
      final originalFile = await cacheService.fetch(original.url);
      final ownFile = await cacheService.fetch(picture.url);

      return _publish(await SimilarityService.computeSimilarity(
        record: record,
        originalBytes: await originalFile.readAsBytes(),
        ownBytes: await ownFile.readAsBytes(),
      ));
    } catch (error) {
      debugPrint('comparePictures error: $error');
      return _publish(null);
    }
  }

  double? _publish(double? value) {
    _similarity = value;
    if (!similarityChanges.isClosed) {
      similarityChanges.add(value);
    }
    return value;
  }
}
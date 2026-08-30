import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_img/domain/timelapse_state.dart';
import 'package:time_machine_img/services/timelapse_service.dart';
import 'package:time_machine_img/time_machine_img.dart';
import 'package:time_machine_net/time_machine_net.dart';

import '../services/database_service.dart';

class TimelapseController extends ValueNotifier<TimelapseState> {
  TimelapseController({
    required this.cacheService,
    this.databaseService,
  }) : super(UninitializedState());

  final _cancelToken = CancelToken();
  final CacheService cacheService;
  final DatabaseService? databaseService;
  TimelapseService? _service;

  @override
  void dispose() {
    _cancelToken.cancel();
    _service?.dispose();
    super.dispose();
  }

  Future<void> loadRecord(int? id) async {
    if (id == null) {
      return;
    }
    final record = await databaseService?.loadRecord(id);
    if (record == null) {
      return;
    }

    record.picture = await databaseService?.createRepository<Picture>().getById(record.pictureId);

    final originalId = record.originalId;
    if (originalId != null) {
      record.original = await databaseService?.createRepository<Picture>().getById(originalId);
    }

    final data = await _createTimelapse(record);
    if (data == null) {
      value = FailedState();
    } else {
      value = FinishedState(record: record, data: data);
    }
  }

  Future<Uint8List?> _createTimelapse(Record record) async {
    value = DownloadingState(progress: 0, record: record);
    final picture = record.picture;
    final original = record.original;
    if (picture == null || original == null) {
      return null;
    }
    final originalFile = await cacheService.fetch(original.url);
    final ownFile = await cacheService.fetch(picture.url);

    final service = await TimelapseService.download(
      onReceiveProgress: (cur, tot) {
        value = RenderingState(
          progress: clampDouble(cur / tot, 0, 1),
          record: record,
        );
      },
      cancelToken: _cancelToken,
    );

    value = RenderingState(progress: 0, record: record);
    final originalViewPort = Record.tryParseViewPort(record.originalViewPort);
    final pictureViewPort = Record.tryParseViewPort(record.pictureViewPort);
    final intersection = originalViewPort == null || pictureViewPort == null
        ? null
        : originalViewPort.intersection(pictureViewPort);

    final originalImage = await cropImageFile(
      file: originalFile,
      viewPort: originalViewPort,
      intersection: intersection,
    );
    final ownImage = await cropImageFile(
      file: ownFile,
      viewPort: pictureViewPort,
      intersection: intersection,
    );
    if (originalImage == null || ownImage == null) {
      return null;
    }

    return service.generateVideo(
      firstImage: originalImage,
      secondImage: ownImage,
      width: 512,
      height: 512,
      duration: Duration(seconds: 3),
      fps: 1,
      onReceiveProgress: (cur, tot) {
        value = RenderingState(
          progress: clampDouble(cur / tot, 0, 1),
          record: record,
        );
      }
    );
  }
}
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
    required this.duration,
    this.databaseService,
    this.frameSize = 256,
  }) : super(UninitializedState());

  final _cancelToken = CancelToken();
  final CacheService cacheService;
  final DatabaseService? databaseService;
  final Duration duration;
  final int frameSize;
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

    final (width, height) = TimelapseService.computeTargetSize(
      originalImage,
      maxDimension: frameSize,
    );
    value = DownloadingState(progress: 0, record: record);
    final service = await TimelapseService.load(
      width: width,
      height: height,
      cancelToken: _cancelToken,
      onReceiveProgress: (received, total) {
        if (total <= 0) return;
        value = DownloadingState(
          progress: clampDouble(received / total, 0, 1),
          record: record,
        );
      },
    );

    value = RenderingState(progress: 0, record: record);
    return service.generateVideo(
      firstImage: originalImage,
      secondImage: ownImage,
      duration: duration,
      fps: 4,
      onReceiveProgress: (cur, tot) {
        value = RenderingState(
          progress: clampDouble(cur / tot, 0, 1),
          record: record,
        );
      }
    );
  }
}
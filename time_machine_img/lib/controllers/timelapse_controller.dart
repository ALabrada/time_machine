import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_img/controllers/playback_controller.dart';
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
    this.playbackController,
    ConfigurationService? configurationService,
    int? frameSize,
    int? fps,
  }) : configurationService = configurationService,
       frameSize = frameSize ??
           configurationService?.frameSize ??
           ConfigurationService.defaultFrameSize,
       fps = fps ??
           configurationService?.fps ??
           ConfigurationService.defaultFps,
       super(UninitializedState());

  final _cancelToken = CancelToken();
  final CacheService cacheService;
  final DatabaseService? databaseService;
  final Duration duration;
  final PlaybackController? playbackController;
  final ConfigurationService? configurationService;
  int frameSize;
  int fps;

  TimelapseService? _service;
  Record? _record;
  bool _loading = false;
  bool _pendingReload = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
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
    _record = record;

    record.picture = await databaseService
        ?.createRepository<Picture>()
        .getById(record.pictureId);

    final originalId = record.originalId;
    if (originalId != null) {
      record.original = await databaseService
          ?.createRepository<Picture>()
          .getById(originalId);
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
    _service?.dispose();
    _service = service;

    value = RenderingState(progress: 0, record: record);
    return service.generateVideo(
      firstImage: originalImage,
      secondImage: ownImage,
      duration: duration,
      fps: fps.toDouble(),
      onFrame: (bytes, frameIndex, totalFrames, stepsDone, totalSteps) {
        value = RenderingState(
          progress: clampDouble(stepsDone / totalSteps, 0, 1),
          record: record,
          frame: bytes,
          frameIndex: frameIndex,
          totalFrames: totalFrames,
        );
      },
    );
  }

  Future<void> shareGif() async {
    final state = value;
    if (state is! FinishedState) {
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/timelapse_${DateTime.now().millisecondsSinceEpoch}.gif',
    );
    await file.writeAsBytes(state.data, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
    ));
  }

  void setQuality({int? frameSize, int? fps}) {
    if (frameSize != null && frameSize != this.frameSize) {
      this.frameSize = frameSize;
    }
    if (fps != null && fps != this.fps) {
      this.fps = fps;
    }
    final record = _record;
    if (record == null) {
      return;
    }
    if (_loading) {
      _pendingReload = true;
    } else {
      playbackController?.stop();
      unawaited(_reload(record));
    }
  }

  Future<void> _reload(Record record) async {
    _loading = true;
    try {
      final data = await _createTimelapse(record);
      if (data == null) {
        value = FailedState();
      } else {
        value = FinishedState(record: record, data: data);
      }
    } catch (e, stackTrace) {
      value = FailedState(error: e, stackTrace: stackTrace);
    } finally {
      _loading = false;
      if (_pendingReload && !_disposed) {
        _pendingReload = false;
        unawaited(_reload(record));
      }
    }
  }
}

import 'dart:async';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:listen_sharing_intent/listen_sharing_intent.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:rxdart/rxdart.dart';
import 'package:time_machine_img/services/database_service.dart';

final class SharingService {
  SharingService({this.ignoreUriSchemes = const {}});

  final Set<String> ignoreUriSchemes;
  final imported = PublishSubject<bool>();
  final importedRecords = BehaviorSubject<List<Record>>.seeded([]);
  StreamSubscription? _intentSub;
  Timer? _dropTimer;

  /// Absolute path of the desktop drop-in import folder, once `init` has set
  /// it up. `null` on mobile/web or if the folder could not be created.
  String? dropInFolderPath;

  Future<void> init({
    DatabaseService? databaseService,
  }) async {
    if (databaseService == null || kIsWeb) {
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows) {
      await _initDesktopDropIn(databaseService);
      return;
    }

    _intentSub?.cancel();
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen((value) {
      unawaited(
        _import(
          files: filterSharedMedia(value, ignoreUriSchemes),
          databaseService: databaseService,
        ),
      );
    }, onError: (err) {
      debugPrint("getIntentDataStream error: $err");
    });

    final initialData = await ReceiveSharingIntent.instance.getInitialMedia();
    await _import(
      files: filterSharedMedia(initialData, ignoreUriSchemes),
      databaseService: databaseService,
    );
    await ReceiveSharingIntent.instance.reset();
  }

  void dispose() {
    _intentSub?.cancel();
    _intentSub = null;
    _dropTimer?.cancel();
    _dropTimer = null;
  }

  /// On desktop platforms there is no share intent to receive, so the
  /// application watches a "drop-in" folder instead: any exported archive
  /// (ZIP produced by the export flow) placed there is imported, and then
  /// moved to the `processed/` subfolder so it is not re-imported.
  Future<void> _initDesktopDropIn(DatabaseService databaseService) async {
    final Directory dropDir;
    try {
      final supportDir = await getApplicationSupportDirectory();
      dropDir = Directory(p.join(supportDir.path, 'ImportDrop'));
      await dropDir.create(recursive: true);
      await Directory(p.join(dropDir.path, 'processed')).create(recursive: true);
    } catch (e) {
      debugPrint("SharingService: cannot create drop-in folder: $e");
      return;
    }
    dropInFolderPath = dropDir.path;
    debugPrint("SharingService: watching drop-in folder ${dropDir.path}");
    _dropTimer?.cancel();
    _dropTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_importDroppedFiles(databaseService, dropDir));
    });
  }

  Future<void> _importDroppedFiles(
    DatabaseService databaseService,
    Directory dropDir,
  ) async {
    final processedDir = Directory(p.join(dropDir.path, 'processed'));
    try {
      await for (final entity in dropDir.list()) {
        if (entity is! File) {
          continue;
        }
        unawaited(_importDroppedFile(databaseService, entity, processedDir));
      }
    } catch (e) {
      debugPrint("SharingService: drop-in import error: $e");
    }
  }

  Future<void> _importDroppedFile(
    DatabaseService databaseService,
    File file,
    Directory processedDir,
  ) async {
    try {
      final records = await databaseService.importFile(file: XFile(file.path));
      if (records.isNotEmpty) {
        importedRecords.sink.add(records);
        imported.sink.add(true);
      } else {
        imported.sink.add(false);
      }
    } catch (e) {
      imported.sink.add(false);
      debugPrint("SharingService: cannot import ${file.path}: $e");
    }
    try {
      await file.rename(p.join(processedDir.path, p.basename(file.path)));
    } catch (_) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  Future<void> import({
    required Iterable<XFile> files,
    DatabaseService? databaseService,
  }) async {
    final db = databaseService;
    if (db == null) {
      return;
    }
    for (final file in files) {
      try {
        final records = await db.importFile(file: file);
        if (records.isNotEmpty) {
          importedRecords.sink.add(records);
          imported.sink.add(true);
        } else {
          imported.sink.add(false);
        }
      } catch (e) {
        imported.sink.add(false);
      }
    }
  }

  Future<void> _import({
    required List<SharedMediaFile> files,
    DatabaseService? databaseService,
  }) async {
    await import(
      files: files.map((e) => XFile(e.path)),
      databaseService: databaseService,
    );
  }
}

/// Drops shares whose path is a URI with an ignored scheme. Used to keep the
/// OAuth consent return (`com.fakegem.historylens:/oauth2redirect?...`), which
/// arrives on Android as an ACTION_VIEW intent, from being imported as a
/// shared "url".
List<SharedMediaFile> filterSharedMedia(
  List<SharedMediaFile> files,
  Set<String> ignoreUriSchemes,
) {
  if (files.isEmpty || ignoreUriSchemes.isEmpty) {
    return files;
  }
  return files
      .where((file) =>
          file.type != SharedMediaType.url ||
          !ignoreUriSchemes.contains(Uri.tryParse(file.path)?.scheme))
      .toList();
}
import 'dart:async';

import 'package:listen_sharing_intent/listen_sharing_intent.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:rxdart/rxdart.dart';
import 'package:time_machine_img/services/database_service.dart';

final class SharingService {
  final imported = PublishSubject<bool>();
  final importedRecords = BehaviorSubject<List<Record>>.seeded([]);
  StreamSubscription? _intentSub;

  Future<void> init({
    DatabaseService? databaseService,
  }) async {
    if (databaseService == null) {
      return;
    }

    _intentSub?.cancel();
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen((value) {
      unawaited(_import(files: value, databaseService: databaseService));
    }, onError: (err) {
      print("getIntentDataStream error: $err");
    });

    final initialData = await ReceiveSharingIntent.instance.getInitialMedia();
    await _import(files: initialData, databaseService: databaseService);
    await ReceiveSharingIntent.instance.reset();
  }

  void dispose() {
    _intentSub?.cancel();
    _intentSub = null;
  }

  Future<void> import({
    required Iterable<String> files,
    DatabaseService? databaseService,
  }) async {
    final db = databaseService;
    if (db == null) {
      return;
    }
    for (final file in files) {
      try {
        final records = await db.importFile(sourcePath: file);
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
      files: files.map((e) => e.path),
      databaseService: databaseService,
    );
  }
}
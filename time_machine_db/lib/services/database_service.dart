import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast_web/sembast_web.dart';
import 'package:time_machine_db/time_machine_db.dart';

class DatabaseService {
  DatabaseService({required this.db, this.dataPath});

  final String? dataPath;
  final Database db;
  final _eventsController = StreamController<RepositoryEvent>.broadcast();

  String? get filePath => dataPath == null ? null : p.join(dataPath!, 'files');
  Stream<RepositoryEvent> get events => _eventsController.stream;

  String expandPath(String path) => expandPathGlobal(path, filePath);

  Repository<T> createRepository<T>() => Repository<T>.create(db: db, events: _eventsController.sink);

  static Future<DatabaseService> load({String? dirPath,}) async {
    if (kIsWeb) {
      final path = dirPath ?? '/assets';
      final db = await databaseFactoryWeb.openDatabase('sembast');
      final service = DatabaseService(db: db, dataPath: path);
      return service;
    } else {
      final path = dirPath ?? (await getApplicationDocumentsDirectory()).path;
      final factory = databaseFactoryIo;
      final dataDir = Directory(p.join(path, 'data'));
      await dataDir.create();
      final db = await factory.openDatabase(p.join(dataDir.path, 'sembast.db'));
      final service = DatabaseService(db: db, dataPath: path);
      final filePath = service.filePath;
      if (filePath != null) {
        final files = Directory(filePath);
        await files.create(recursive: true);
      }
      return service;
    }
  }

  Future<bool> deleteFiles(String path) async {
    final dirPath = filePath;
    if (dirPath == null) {
      throw Exception('Cannot save files');
    }
    var file = File(p.join(dirPath, path));
    if (!await file.exists()) {
      return false;
    }
    await file.delete(recursive: true);
    return true;
  }

  Future<String> readText(String path) async {
    final dirPath = await getApplicationDocumentsDirectory();
    var file = File(p.join(dirPath.path, path));
    return await file.readAsString();
  }

  Future<String> writeFile(String path, Object content) async {
    final dirPath = await getApplicationDocumentsDirectory();
    var file = File(p.join(dirPath.path, path));
    file = await file.create(recursive: true);
    if (content is String) {
      file = await file.writeAsString(content);
    } else if (content is Uint8List) {
      file = await file.writeAsBytes(content);
    } else {
      throw Exception('Invalid content');
    }
    return path;
  }
}
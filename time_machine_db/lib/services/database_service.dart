import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast_web/sembast_web.dart';
import 'package:time_machine_db/time_machine_db.dart';

class DatabaseService {
  DatabaseService({required this.db, this.dataPath});

  final String? dataPath;
  final Database db;

  String? get filePath => dataPath == null ? null : p.join(dataPath!, 'files');

  Repository<T> createRepository<T>() => Repository.create(db: db);

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
    if (dirPath == null) {
      throw Exception('Cannot save files');
    }
    var file = File(p.join(dirPath.path, path));
    return await file.readAsString();
  }

  Future<String> writeFile(String path, Object content) async {
    final dirPath = await getApplicationDocumentsDirectory();
    if (dirPath == null) {
      throw Exception('Cannot save files');
    }
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

class Repository<T> {
  final StoreRef<int, Map<String, Object?>> box;
  final Database db;
  final T Function(Map<String, dynamic> json) fromJson;
  final Map<String, dynamic> Function(T item) toJson;
  final int? Function(T item) getKey;
  final void Function(T item, int id) setKey;

  const Repository({
    required this.box,
    required this.db,
    required this.fromJson,
    required this.toJson,
    required this.getKey,
    required this.setKey,
  });

  factory Repository.create({required Database db}) {
    final storeId = T.toString().toLowerCase();
    switch (T) {
      case Picture:
        return Repository<Picture>(
          box: intMapStoreFactory.store(storeId),
          db: db,
          fromJson: Picture.fromJson,
          toJson: (x) => x.toJson(),
          getKey: (x) => x.localId,
          setKey: (x, v) => x.localId = v,
        ) as Repository<T>;
      case Record:
        return Repository<Record>(
          box: intMapStoreFactory.store(storeId),
          db: db,
          fromJson: Record.fromJson,
          toJson: (x) => x.toJson(),
          getKey: (x) => x.localId,
          setKey: (x, v) => x.localId = v,
        ) as Repository<T>;
      default:
        throw Exception("Invalid repository type: ${T.runtimeType.toString()}");
    }
  }

  Future<bool> delete(Object id)  async {
    final record = box.record(id as int);
    return await record.delete(db) != null;
  }

  Future<List<T>> find(Finder? finder) async {
    final items = await box.find(db, finder: finder);
    return List.generate(items.length, (index) {
      final item = fromJson(items[index].value);
      setKey(item, items[index].key);
      return item;
    });
  }

  Future<T?> findFirst(Finder? finder) async {
    final data = await box.findFirst(db, finder: finder);
    if (data == null) {
      return null;
    }
    final item = fromJson(data.value);
    setKey(item, data.key);
    return item;
  }

  Future<T?> getById(Object id) async {
    final record = box.record(id as int);
    final data = await record.get(db);
    if (data == null) {
      return null;
    }
    final item = fromJson(data);
    setKey(item, id);
    return item;
  }

  Future<T> insert(T entity) async {
    final id = await box.add(db, toJson(entity));
    setKey(entity, id);
    return entity;
  }

  Future<List<T>> list() => find(null);

  Future<void> update(T entity) async {
    final id = getKey(entity);
    if (id == null) {
      return;
    }
    await box.record(id).put(db, toJson(entity));
  }

  Future<T> upsert(T entity) async {
    final id = getKey(entity);
    if (id == null) {
      return await insert(entity);
    } else {
      await update(entity);
      return entity;
    }
  }
}
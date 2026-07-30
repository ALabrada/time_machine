import 'dart:async';
import 'package:sembast/sembast_io.dart';
import 'package:sembast_web/sembast_web.dart';
import 'package:time_machine_db/time_machine_db.dart';

class Repository<T> {
  final StoreRef<int, Map<String, Object?>> box;
  final Database db;
  final T Function(Map<String, dynamic> json) fromJson;
  final Map<String, dynamic> Function(T item) toJson;
  final int? Function(T item) getKey;
  final void Function(T item, int id) setKey;
  final void Function(T item, DateTime dt)? setDeleted;
  final StreamSink<RepositoryEvent>? events;

  const Repository({
    required this.box,
    required this.db,
    required this.fromJson,
    required this.toJson,
    required this.getKey,
    required this.setKey,
    this.setDeleted,
    this.events,
  });

  factory Repository.create({
    required Database db,
    StreamSink<RepositoryEvent>? events,
  }) {
    if (T == Picture) {
      return Repository<Picture>(
        box: intMapStoreFactory.store('picture'),
        db: db,
        fromJson: Picture.fromJson,
        toJson: (x) => x.toJson(),
        getKey: (x) => x.localId,
        setKey: (x, v) => x.localId = v,
        setDeleted: (x, v) => x.deletedAt = v,
        events: events,
      ) as Repository<T>;
    }
    if (T == Record) {
      return Repository<Record>(
        box: intMapStoreFactory.store('record'),
        db: db,
        fromJson: Record.fromJson,
        toJson: (x) => x.toJson(),
        getKey: (x) => x.localId,
        setKey: (x, v) => x.localId = v,
        setDeleted: (x, v) => x.deletedAt = v,
        events: events,
      ) as Repository<T>;
    }
    throw Exception("Invalid repository type: ${T.toString()}");
  }

  Future<bool> delete(Object id)  async {
    final record = box.record(id as int);
    final raw = await record.get(db);
    if (raw == null || await record.delete(db) == null) {
      return false;
    }
    final item = fromJson(Map<String, dynamic>.from(raw));
    setKey(item, id);
    setDeleted?.call(item, DateTime.now());
    events?.add(EntityRemoved(item));
    return true;
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
    events?.add(EntityInserted(entity));
    return entity;
  }

  Future<List<T>> list() => find(null);

  Future<void> update(T entity) async {
    final id = getKey(entity);
    if (id == null) {
      return;
    }
    await box.record(id).put(db, toJson(entity));
    events?.add(EntityUpdated(entity));
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

abstract class RepositoryEvent {}

class EntityRemoved<T> implements RepositoryEvent {
  final T entity;
  const EntityRemoved(this.entity);
}

class EntityInserted<T> implements RepositoryEvent {
  final T entity;
  const EntityInserted(this.entity);
}

class EntityUpdated<T> implements RepositoryEvent {
  final T entity;
  const EntityUpdated(this.entity);
}
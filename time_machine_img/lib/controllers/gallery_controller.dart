import 'dart:async';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_img/domain/gallery_section.dart';
import 'package:time_machine_img/services/database_service.dart';
import 'package:time_machine_img/services/sharing_service.dart';
import 'package:time_machine_res/controllers/task_manager.dart';

class GalleryController with TaskManager {
  GalleryController({this.sharingService}) {
    searchController.addListener(() {
      _searchCriteria.value = searchController.text;
    });
  }

  final SharingService? sharingService;
  final searchController = TextEditingController();
  final _searchCriteria = BehaviorSubject.seeded('');

  final BehaviorSubject<bool> isEditing = BehaviorSubject.seeded(false);
  final BehaviorSubject<List<GallerySection>> sections = BehaviorSubject();
  final BehaviorSubject<Set<Record>> selection = BehaviorSubject.seeded({});
  DatabaseService? databaseService;

  StreamSubscription? _searchSubscription, _importSubscription;

  void dispose() {
    _searchSubscription?.cancel();
    _searchSubscription = null;
    _importSubscription?.cancel();
    _importSubscription = null;
  }

  void cancelEditing() {
    selection.value = {};
    isEditing.value = false;
  }

  void clearSelection() {
    selection.value = {};
  }

  void toggleSelection(Record record) {
    final selection = this.selection.value;
    if (!selection.add(record)) {
      selection.remove(record);
    }
    this.selection.value = selection;
    if (!isEditing.value) {
      isEditing.value = true;
    }
  }

  Future<void> importRecords({
    DatabaseService? databaseService,
  }) async {
    final selection = await FilePicker.platform.pickFiles();
    if (selection == null) {
      return;
    }
    await sharingService?.import(
      files: selection.paths.nonNulls,
      databaseService: databaseService,
    );
    await _reloadElements();
  }

  Future<void> removeRecords() async {
    for (final record in selection.value) {
      final dbRecord = await loadRecord(record.localId);
      await databaseService?.removeRecord(dbRecord ?? record);
    }
    await _reloadElements();
  }

  Future<void> export({String? dialogTitle}) async {
    final databaseService = this.databaseService;
    if (selection.value.isEmpty || databaseService == null) {
      return;
    }
    final data = await execute(() async => await databaseService.exportMany(
      records: [
        for (final item in selection.value)
          await loadRecord(item.localId) ?? item,
      ],
    ));
    if (data == null) {
      return;
    }
    await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: 'export',
      bytes: data,
    );
  }

  Stream<List<GallerySection>> loadAndFilterElements({
    DatabaseService? databaseService,
  }) async* {
    await sharingService?.init(databaseService: databaseService);

    _searchSubscription?.cancel();
    _searchSubscription = _searchCriteria.throttleTime(Duration(milliseconds: 200)).distinct()
      .listen((q) {
        unawaited(_reloadElements(query: q));
      });

    _importSubscription?.cancel();
    _importSubscription = sharingService?.importedRecords
      .listen((q) {
        unawaited(_reloadElements());
      });

    this.databaseService = databaseService;
    await _reloadElements();
    yield* sections;
  }

  Future<Record?> loadRecord(int? id) async {
    if (id == null) {
      return null;
    }
    final record = await databaseService?.createRepository<Record>().getById(id);
    if (record == null) {
      return null;
    }

    record.picture = await databaseService?.createRepository<Picture>().getById(record.pictureId);

    final originalId = record.originalId;
    if (originalId != null) {
      record.original = await databaseService?.createRepository<Picture>().getById(originalId);
    }

    return record;
  }

  Future<Picture?> loadPicture(int id) async {
    return await databaseService?.createRepository<Picture>().getById(id);
  }

  Future<void> _reloadElements({String? query}) async {
    final text = (query ?? searchController.text).trim();
    final words = text.split(r'\s+');
    words.removeWhere((e) => e.length < 2);    
    final items = await databaseService?.findRecords(words);
    if (items == null) {
      return;
    }
    _updateSections(items);
  }

  void _updateSections(List<Record> records) {
    final dateFormat = DateFormat.yMEd();
    sections.value = records
        .groupListsBy((x) => dateFormat.format(x.createdAt))
        .entries
        .sortedByCompare((e) => e.value.first.createdAt, (x, y) => -x.compareTo(y))
        .map((e) => GallerySection(
          title: e.key,
          elements: e.value,
        ))
        .toList();
  }
}
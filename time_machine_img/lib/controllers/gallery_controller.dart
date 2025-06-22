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
  }

  Future<void> removeRecords() async {
    for (final record in selection.value) {
      await databaseService?.removeRecord(record);
    }
  }

  Future<void> export({String? dialogTitle}) async {
    final databaseService = this.databaseService;
    if (selection.value.isEmpty || databaseService == null) {
      return;
    }
    final data = await execute(() => databaseService.exportMany(
      records: selection.value.toList(),
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

  List<GallerySection> filter(List<GallerySection> sections, {String? criteria}) {
    final text = (criteria ?? searchController.text).trim();
    if (sections.isEmpty || text.isEmpty) {
      return sections;
    }
    final words = text
        .toLowerCase()
        .split(r'\s+');
    if (words.isEmpty) {
      return sections;
    }
    return sections
        .map((s) {
          return GallerySection(
            title: s.title,
            elements: s.elements.where((e) => e.matches(words)).toList(),
          );
        })
        .where((s) => s.elements.isNotEmpty)
        .toList();
  }

  Stream<List<GallerySection>> loadAndFilterElements({
    DatabaseService? databaseService,
  }) async* {
    await sharingService?.init(databaseService: databaseService);
    yield* CombineLatestStream.combine3(
        reloadElements(databaseService: databaseService),
        _searchCriteria.throttleTime(Duration(milliseconds: 200)).distinct(),
        sharingService?.importedRecords ?? Stream.value([]),
        (a, b, _) => filter(a, criteria: b),
    );
  }

  Stream<List<GallerySection>> reloadElements({
    DatabaseService? databaseService,
  }) async* {
    this.databaseService = databaseService;
    final items = await databaseService?.createRepository<Record>().list();
    if (items == null) {
      return;
    }
    _updateSections(items);
    yield* sections;
  }

  Future<Picture?> loadPicture(int id) async {
    return await databaseService?.createRepository<Picture>().getById(id);
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

extension SearchExtension on Record {
  bool matches(List<String> words) {
    final original = this.original;
    final picture = this.picture;
    return words.every((w) {
      if (original != null && original.text.toLowerCase().contains(w)) {
        return true;
      }
      if (picture != null && picture.text.toLowerCase().contains(w)) {
        return true;
      }
      return false;
    });
  }
}
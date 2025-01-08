import 'dart:async';

import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_img/domain/gallery_section.dart';

class GalleryController {
  GalleryController();

  final BehaviorSubject<List<GallerySection>> sections = BehaviorSubject();
  DatabaseService? databaseService;

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
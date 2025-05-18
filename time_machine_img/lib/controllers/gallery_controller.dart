import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_img/domain/gallery_section.dart';

class GalleryController {
  GalleryController() {
    searchController.addListener(() {
      _searchCriteria.value = searchController.text;
    });
  }

  final searchController = TextEditingController();
  final _searchCriteria = BehaviorSubject.seeded('');

  final BehaviorSubject<List<GallerySection>> sections = BehaviorSubject();
  DatabaseService? databaseService;

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
  }) {
    return CombineLatestStream.combine2(
        reloadElements(databaseService: databaseService),
        _searchCriteria.throttleTime(Duration(milliseconds: 200)).distinct(),
        (a, b) => filter(a, criteria: b),
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
import 'package:sembast/sembast.dart';
import 'package:time_machine_core/domain/date_time_converter.dart';
import 'package:time_machine_core/domain/record_mirror.dart';

import '../services/repository.dart';

extension RecordMirrorRepository on Repository<RecordMirror> {
  Future<RecordMirror?> findByIdAndCloud(String id, String cloudId) async {
    final finder = Finder(filter: Filter.and([
      Filter.equals('id', id),
      Filter.equals('cloudId', cloudId),
    ]));
    final result = await findFirst(finder);
    return result;
  }

  Future<List<RecordMirror>> findByRecord(int recordId) async {
    final finder = Finder(filter: Filter.equals('recordId', recordId));
    final result = await find(finder);
    return result;
  }

  Future<List<RecordMirror>> findByCloud(String cloudId) async {
    final finder = Finder(filter: Filter.equals('cloudId', cloudId));
    final result = await find(finder);
    return result;
  }

  Future<RecordMirror?> findByRecordAndCloud(int recordId, String cloudId) async {
    final finder = Finder(filter: Filter.and([
      Filter.equals('recordId', recordId),
      Filter.equals('cloudId', cloudId),
    ]));
    final result = await findFirst(finder);
    return result;
  }

  Future<List<RecordMirror>> findDeletedRecordsSince({DateTime? since}) async {
    final finder = Finder(filter: Filter.and([
      Filter.notNull('deletedAt'),
      if (since != null)
        Filter.greaterThan('deletedAt', DateTimeConverter().toJson(since)),
    ]));
    final result = await find(finder);
    return result;
  }
}
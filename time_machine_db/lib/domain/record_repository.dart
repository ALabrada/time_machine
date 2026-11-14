import 'package:sembast/sembast.dart';
import 'package:time_machine_core/domain/date_time_converter.dart';
import 'package:time_machine_core/domain/record.dart';

import '../services/repository.dart';

extension RecordRepository on Repository<Record> {
  Future<List<Record>> findRecordsWithPictures(List<int> pictureIds) async {
    final finder = Finder(
      filter: Filter.or([
        Filter.inList('originalId', pictureIds),
        Filter.inList('pictureId', pictureIds),
      ]),
    );
    final result = await find(finder);
    return result;
  }

  Future<Record?> findRecordByPictureId(int pictureId) async {
    final finder = Finder(filter: Filter.equals('pictureId', pictureId), limit: 1);
    final result = await findFirst(finder);
    return result;
  }

  Future<List<Record>> findVisitedRecords({
    int limit = 20,
  }) async {
    final finder = Finder(
      filter: Filter.notNull('visitedAt'),
      sortOrders: [
        SortOrder('visitedAt', false),
      ],
      limit: limit,
    );
    final result = await find(finder);
    return result;
  }

  Future<List<Record>> findUpdatedRecords({
    DateTime? since,
  }) async {
    final finder = Finder(
      filter: since == null ? null : Filter.greaterThan('updateAt', DateTimeConverter().toJson(since)),
      sortOrders: [
        SortOrder('updateAt', false),
      ],
    );
    final result = await find(finder);
    return result;
  }

  Future<List<Record>> paginate({
    int offset = 0,
    int limit = 20,
  }) async {
    final finder = Finder(
      sortOrders: [
        SortOrder('createdAt', false),
        SortOrder('pictureId'),
      ],
      offset: offset,
      limit: limit,
    );
    final result = await find(finder);
    return result;
  }
}
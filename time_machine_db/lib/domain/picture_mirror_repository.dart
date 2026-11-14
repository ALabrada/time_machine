import 'package:sembast/sembast.dart';
import 'package:time_machine_core/domain/date_time_converter.dart';
import 'package:time_machine_core/domain/picture_mirror.dart';

import '../services/repository.dart';

extension PictureMirrorRepository on Repository<PictureMirror> {
  Future<PictureMirror?> findByIdAndCloud(String id, String cloudId) async {
    final finder = Finder(filter: Filter.and([
      Filter.equals('id', id),
      Filter.equals('cloudId', cloudId),
    ]));
    final result = await findFirst(finder);
    return result;
  }

  Future<List<PictureMirror>> findByPicture(int pictureId) async {
    final finder = Finder(filter: Filter.equals('pictureId', pictureId));
    final result = await find(finder);
    return result;
  }

  Future<List<PictureMirror>> findByCloud(String cloudId) async {
    final finder = Finder(filter: Filter.equals('cloudId', cloudId));
    final result = await find(finder);
    return result;
  }

  Future<PictureMirror?> findByPictureAndCloud(int pictureId, String cloudId) async {
    final finder = Finder(filter: Filter.and([
      Filter.equals('pictureId', pictureId),
      Filter.equals('cloudId', cloudId),
    ]));
    final result = await findFirst(finder);
    return result;
  }

  Future<List<PictureMirror>> findDeletedRecordsSince({DateTime? since}) async {
    final finder = Finder(filter: Filter.and([
      Filter.notNull('deletedAt'),
      if (since != null)
        Filter.greaterThan('deletedAt', DateTimeConverter().toJson(since)),
    ]));
    final result = await find(finder);
    return result;
  }
}
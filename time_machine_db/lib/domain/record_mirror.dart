import 'package:time_machine_db/time_machine_db.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:sembast/sembast.dart';

part 'record_mirror.g.dart';

@JsonSerializable()
class RecordMirror {
  RecordMirror({
    required this.id,
    required this.recordId,
    required this.createdAt,
    required this.updatedAt,
    this.localId,
    this.cloudId,
    this.deletedAt,
    this.record,
  });

  String id;
  @JsonKey(includeToJson: false, includeFromJson: false)
  int? localId;
  int recordId;
  String? cloudId;
  @DateTimeConverter()
  DateTime createdAt;
  @DateTimeConverter()
  DateTime updatedAt;
  @DateTimeConverter()
  DateTime? deletedAt;

  @JsonKey(includeFromJson: false, includeToJson: false)
  Record? record;

  @JsonKey(includeFromJson: false, includeToJson: false)
  DateTime get lastDate => deletedAt ?? updatedAt;

  @JsonKey(includeFromJson: false, includeToJson: false)
  CloudMetadata get metadata => CloudMetadata(
    id: id,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );
  set metadata(CloudMetadata metadata) {
    id = metadata.id;
    createdAt = metadata.createdAt;
    updatedAt = metadata.updatedAt;
    deletedAt = metadata.deletedAt;
  }

  factory RecordMirror.fromJson(Map<String, dynamic> json) => _$RecordMirrorFromJson(json);

  Map<String, dynamic> toJson() => _$RecordMirrorToJson(this);
}

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
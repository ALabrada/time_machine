import 'package:time_machine_db/time_machine_db.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:sembast/sembast.dart';

part 'picture_mirror.g.dart';

@JsonSerializable()
class PictureMirror {
  PictureMirror({
    required this.id,
    required this.pictureId,
    required this.createdAt,
    required this.updatedAt,
    this.localId,
    this.cloudId,
    this.deletedAt,
    this.picture,
  });

  String id;
  @JsonKey(includeToJson: false, includeFromJson: false)
  int? localId;
  int pictureId;
  String? cloudId;
  @DateTimeConverter()
  DateTime createdAt;
  @DateTimeConverter()
  DateTime updatedAt;
  @DateTimeConverter()
  DateTime? deletedAt;

  @JsonKey(includeFromJson: false, includeToJson: false)
  Picture? picture;

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

  factory PictureMirror.fromJson(Map<String, dynamic> json) => _$PictureMirrorFromJson(json);

  Map<String, dynamic> toJson() => _$PictureMirrorToJson(this);
}

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
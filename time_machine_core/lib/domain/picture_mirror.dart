import 'package:json_annotation/json_annotation.dart';

import 'cloud_metadata.dart';
import 'date_time_converter.dart';
import 'picture.dart';

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
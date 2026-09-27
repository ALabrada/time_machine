import 'package:json_annotation/json_annotation.dart';

import 'cloud_metadata.dart';
import 'date_time_converter.dart';
import 'record.dart';

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
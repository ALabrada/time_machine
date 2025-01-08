import 'package:time_machine_db/time_machine_db.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:sembast/sembast.dart';

part 'record.g.dart';

@JsonSerializable()
class Record {
  Record({
    required this.pictureId,
    required this.createdAt,
    required this.updateAt,
    this.originalId,
    this.localId,
    this.original,
    this.picture,
  });

  @JsonKey(includeToJson: false, includeFromJson: false)
  int? localId;
  int? originalId;
  int pictureId;
  DateTime createdAt;
  DateTime updateAt;

  @JsonKey(includeFromJson: false, includeToJson: false)
  Picture? original;
  @JsonKey(includeFromJson: false, includeToJson: false)
  Picture? picture;

  factory Record.fromJson(Map<String, dynamic> json) => _$RecordFromJson(json);

  Map<String, dynamic> toJson() => _$RecordToJson(this);
}
import 'package:json_annotation/json_annotation.dart';

part 'cloud_metadata.g.dart';

@JsonSerializable()
class CloudMetadata {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  DateTime get lastDate => deletedAt ?? updatedAt;

  const CloudMetadata({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory CloudMetadata.fromJson(Map<String, dynamic> json) => _$CloudMetadataFromJson(json);

  Map<String, dynamic> toJson() => _$CloudMetadataToJson(this);
}
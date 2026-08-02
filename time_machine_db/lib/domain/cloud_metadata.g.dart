// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cloud_metadata.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CloudMetadata _$CloudMetadataFromJson(Map<String, dynamic> json) =>
    CloudMetadata(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.parse(json['deletedAt'] as String),
    );

Map<String, dynamic> _$CloudMetadataToJson(CloudMetadata instance) =>
    <String, dynamic>{
      'id': instance.id,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'deletedAt': instance.deletedAt?.toIso8601String(),
    };

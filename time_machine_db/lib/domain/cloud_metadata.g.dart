// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cloud_metadata.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CloudMetadata _$CloudMetadataFromJson(Map<String, dynamic> json) =>
    CloudMetadata(
      id: json['id'] as String,
      createdAt:
          const DateTimeConverter().fromJson(json['createdAt'] as Object),
      updatedAt:
          const DateTimeConverter().fromJson(json['updatedAt'] as Object),
      deletedAt: _$JsonConverterFromJson<Object, DateTime>(
          json['deletedAt'], const DateTimeConverter().fromJson),
    );

Map<String, dynamic> _$CloudMetadataToJson(CloudMetadata instance) =>
    <String, dynamic>{
      'id': instance.id,
      'createdAt': const DateTimeConverter().toJson(instance.createdAt),
      'updatedAt': const DateTimeConverter().toJson(instance.updatedAt),
      'deletedAt': _$JsonConverterToJson<Object, DateTime>(
          instance.deletedAt, const DateTimeConverter().toJson),
    };

Value? _$JsonConverterFromJson<Json, Value>(
  Object? json,
  Value? Function(Json json) fromJson,
) =>
    json == null ? null : fromJson(json as Json);

Json? _$JsonConverterToJson<Json, Value>(
  Value? value,
  Json? Function(Value value) toJson,
) =>
    value == null ? null : toJson(value);

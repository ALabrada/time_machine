// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'record_mirror.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RecordMirror _$RecordMirrorFromJson(Map<String, dynamic> json) => RecordMirror(
      id: json['id'] as String,
      recordId: (json['recordId'] as num).toInt(),
      createdAt:
          const DateTimeConverter().fromJson(json['createdAt'] as Object),
      updatedAt:
          const DateTimeConverter().fromJson(json['updatedAt'] as Object),
      cloudId: json['cloudId'] as String?,
      deletedAt: _$JsonConverterFromJson<Object, DateTime>(
          json['deletedAt'], const DateTimeConverter().fromJson),
    );

Map<String, dynamic> _$RecordMirrorToJson(RecordMirror instance) =>
    <String, dynamic>{
      'id': instance.id,
      'recordId': instance.recordId,
      'cloudId': instance.cloudId,
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

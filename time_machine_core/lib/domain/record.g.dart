// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Record _$RecordFromJson(Map<String, dynamic> json) => Record(
      pictureId: (json['pictureId'] as num).toInt(),
      createdAt:
          const DateTimeConverter().fromJson(json['createdAt'] as Object),
      updateAt: const DateTimeConverter().fromJson(json['updateAt'] as Object),
      visitedAt: _$JsonConverterFromJson<Object, DateTime>(
          json['visitedAt'], const DateTimeConverter().fromJson),
      originalId: (json['originalId'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toDouble(),
      width: (json['width'] as num?)?.toDouble(),
      originalViewPort: json['originalViewPort'] as String?,
      pictureViewPort: json['pictureViewPort'] as String?,
    );

Map<String, dynamic> _$RecordToJson(Record instance) => <String, dynamic>{
      'originalId': instance.originalId,
      'pictureId': instance.pictureId,
      'createdAt': const DateTimeConverter().toJson(instance.createdAt),
      'updateAt': const DateTimeConverter().toJson(instance.updateAt),
      'visitedAt': _$JsonConverterToJson<Object, DateTime>(
          instance.visitedAt, const DateTimeConverter().toJson),
      'height': instance.height,
      'width': instance.width,
      'originalViewPort': instance.originalViewPort,
      'pictureViewPort': instance.pictureViewPort,
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

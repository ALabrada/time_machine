// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Record _$RecordFromJson(Map<String, dynamic> json) => Record(
      pictureId: (json['pictureId'] as num).toInt(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updateAt: DateTime.parse(json['updateAt'] as String),
      originalId: (json['originalId'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toDouble(),
      width: (json['width'] as num?)?.toDouble(),
      originalViewPort: json['originalViewPort'] as String?,
      pictureViewPort: json['pictureViewPort'] as String?,
    );

Map<String, dynamic> _$RecordToJson(Record instance) => <String, dynamic>{
      'originalId': instance.originalId,
      'pictureId': instance.pictureId,
      'createdAt': instance.createdAt.toIso8601String(),
      'updateAt': instance.updateAt.toIso8601String(),
      'height': instance.height,
      'width': instance.width,
      'originalViewPort': instance.originalViewPort,
      'pictureViewPort': instance.pictureViewPort,
    };

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
    );

Map<String, dynamic> _$RecordToJson(Record instance) => <String, dynamic>{
      'originalId': instance.originalId,
      'pictureId': instance.pictureId,
      'createdAt': instance.createdAt.toIso8601String(),
      'updateAt': instance.updateAt.toIso8601String(),
    };

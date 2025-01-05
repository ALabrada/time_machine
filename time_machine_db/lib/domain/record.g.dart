// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Record _$RecordFromJson(Map<String, dynamic> json) => Record(
      originalId: json['originalId'] as String,
      pictureId: json['pictureId'] as String,
      localId: (json['localId'] as num?)?.toInt(),
    );

Map<String, dynamic> _$RecordToJson(Record instance) => <String, dynamic>{
      'localId': instance.localId,
      'originalId': instance.originalId,
      'pictureId': instance.pictureId,
    };

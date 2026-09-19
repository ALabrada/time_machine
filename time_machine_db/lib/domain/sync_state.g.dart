// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SyncState _$SyncStateFromJson(Map<String, dynamic> json) => SyncState(
      cloudId: json['cloudId'] as String,
      lastSync: const DateTimeConverter().fromJson(json['lastSync'] as Object),
    );

Map<String, dynamic> _$SyncStateToJson(SyncState instance) => <String, dynamic>{
      'cloudId': instance.cloudId,
      'lastSync': const DateTimeConverter().toJson(instance.lastSync),
    };

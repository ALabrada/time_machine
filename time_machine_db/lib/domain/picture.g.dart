// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'picture.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Picture _$PictureFromJson(Map<String, dynamic> json) => Picture(
      id: json['id'] as String,
      url: json['url'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      localId: (json['localId'] as num?)?.toInt(),
      provider: json['provider'] as String?,
      previewUrl: json['previewUrl'] as String?,
      description: json['description'] as String?,
      altitude: (json['altitude'] as num?)?.toDouble(),
      bearing: (json['bearing'] as num?)?.toDouble(),
      time: json['time'] as String?,
    );

Map<String, dynamic> _$PictureToJson(Picture instance) => <String, dynamic>{
      'id': instance.id,
      'localId': instance.localId,
      'provider': instance.provider,
      'url': instance.url,
      'previewUrl': instance.previewUrl,
      'description': instance.description,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'altitude': instance.altitude,
      'bearing': instance.bearing,
      'time': instance.time,
    };

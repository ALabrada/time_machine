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
      provider: json['provider'] as String?,
      previewUrl: json['previewUrl'] as String?,
      description: json['description'] as String?,
      altitude: (json['altitude'] as num?)?.toDouble(),
      bearing: (json['bearing'] as num?)?.toDouble(),
      time: json['time'] as String?,
      margin: json['margin'] as String?,
      site: json['site'] as String?,
      visitedAt: _$JsonConverterFromJson<Object, DateTime>(
          json['visitedAt'], const DateTimeConverter().fromJson),
    );

Map<String, dynamic> _$PictureToJson(Picture instance) => <String, dynamic>{
      'id': instance.id,
      'provider': instance.provider,
      'url': instance.url,
      'previewUrl': instance.previewUrl,
      'description': instance.description,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'altitude': instance.altitude,
      'bearing': instance.bearing,
      'time': instance.time,
      'margin': instance.margin,
      'site': instance.site,
      'visitedAt': _$JsonConverterToJson<Object, DateTime>(
          instance.visitedAt, const DateTimeConverter().toJson),
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

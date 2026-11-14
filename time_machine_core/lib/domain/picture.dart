import 'package:json_annotation/json_annotation.dart';

import 'date_time_converter.dart';
import 'location.dart';

part 'picture.g.dart';

@JsonSerializable()
class Picture {
  Picture({
    required this.id,
    required this.url,
    required this.latitude,
    required this.longitude,
    this.localId,
    this.provider,
    this.previewUrl,
    this.description,
    this.altitude,
    this.bearing,
    this.time,
    this.margin,
    this.site,
    this.visitedAt,
    this.fileHash,
  });

  String id;
  @JsonKey(includeToJson: false, includeFromJson: false)
  int? localId;
  String? provider;
  String url;
  String? previewUrl;
  String? description;
  double latitude;
  double longitude;
  double? altitude;
  double? bearing;
  String? time;
  String? margin;
  String? site;
  @DateTimeConverter()
  DateTime? visitedAt;
  String? fileHash;

  @JsonKey(includeToJson: false, includeFromJson: false)
  Location get location => Location(lat: latitude, lng: longitude);
  set location(Location value) {
    latitude = value.lat;
    longitude = value.lng;
  }

  @JsonKey(includeToJson: false, includeFromJson: false)
  String get text {
    final time = this.time;
    if (time == null) {
      return description ?? '';
    }
    return '$description ($time)';
  }

  factory Picture.fromJson(Map<String, dynamic> json) => _$PictureFromJson(json);

  Map<String, dynamic> toJson() => _$PictureToJson(this);

  Picture copy({
    String? id,
    int? localId,
    String? provider,
    String? url,
    String? previewUrl,
    String? description,
    double? latitude,
    double? longitude,
    double? altitude,
    double? bearing,
    String? time,
    String? margin,
    String? site,
    DateTime? visitedAt,
    DateTime? deletedAt,
    String? cloudId,
    String? fileHash,
  }) => Picture(
    id: id ?? this.id,
    localId: localId ?? this.localId,
    provider: provider ?? this.provider,
    url: url ?? this.url,
    previewUrl: previewUrl ?? this.previewUrl,
    description: description ?? this.description,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    altitude: altitude ?? this.altitude,
    bearing: bearing ?? this.bearing,
    time: time ?? this.time,
    margin: margin ?? this.margin,
    site: site ?? this.site,
    visitedAt: visitedAt ?? this.visitedAt,
    fileHash: fileHash ?? this.fileHash,
  );
}
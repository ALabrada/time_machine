import 'package:time_machine_db/time_machine_db.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:sembast/sembast.dart';

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
  });

  String id;
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

  @JsonKey(includeToJson: false, includeFromJson: false)
  Location get location => Location(lat: latitude, lng: longitude);
  set location(Location value) {
    latitude = value.lat;
    longitude = value.lng;
  }

  factory Picture.fromJson(Map<String, dynamic> json) => _$PictureFromJson(json);

  Map<String, dynamic> toJson() => _$PictureToJson(this);
}

extension PictureRepository on Repository<Picture> {
  Future<Picture?> findPictureByIdAndProvider(int id, String provider) async {
    final finder = Finder(filter: Filter.and([
      Filter.equals('id', id),
      Filter.equals('provider', provider),
    ]));
    final result = await findFirst(finder);
    return result;
  }
}
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
    this.margin,
    this.site,
    this.visitedAt,
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

  Future<List<Picture>> findPicturesWithText(List<String> keywords, {
    int limit = 20,
    List<String> providers = const[],
  }) async {
    final finder = Finder(
      filter: Filter.and([
        for (final word in keywords)
          Filter.matches('description', word),
        if (providers.isNotEmpty)
          Filter.inList('provider', providers),
      ]),
      sortOrders: [
        SortOrder('visitedAt', false, true),
      ],
      limit: limit,
    );
    final result = await find(finder);
    return result;
  }

  Future<List<Picture>> findVisitedPictures({
    int limit = 20,
    List<String> providers = const[],
  }) async {
    final finder = Finder(
      filter: providers.isEmpty ? Filter.notNull('visitedAt') : Filter.and([
        Filter.notNull('visitedAt'),
        Filter.inList('provider', providers),
      ]),
      sortOrders: [
        SortOrder('visitedAt', false),
      ],
      limit: limit,
    );
    final result = await find(finder);
    return result;
  }
}
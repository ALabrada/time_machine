import 'dart:math';

import 'package:time_machine_db/time_machine_db.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:sembast/sembast.dart';

part 'record.g.dart';

@JsonSerializable()
class Record {
  Record({
    required this.pictureId,
    required this.createdAt,
    required this.updateAt,
    this.originalId,
    this.localId,
    this.original,
    this.picture,
    this.height,
    this.width,
    this.originalViewPort,
    this.pictureViewPort,
  });

  @JsonKey(includeToJson: false, includeFromJson: false)
  int? localId;
  int? originalId;
  int pictureId;
  DateTime createdAt;
  DateTime updateAt;

  @JsonKey(includeFromJson: false, includeToJson: false)
  Picture? original;
  @JsonKey(includeFromJson: false, includeToJson: false)
  Picture? picture;

  double? height;
  double? width;
  String? originalViewPort;
  String? pictureViewPort;

  @JsonKey(includeFromJson: false, includeToJson: false)
  double? get originalAspectRatio {
    final viewPort = tryParseViewPort(originalViewPort);
    return viewPort == null ? null : viewPort.width / viewPort.height;
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  double? get pictureAspectRatio {
    final viewPort = tryParseViewPort(pictureViewPort);
    return viewPort == null ? null : viewPort.width / viewPort.height;
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  double? get aspectRatio {
    final originalViewPort = tryParseViewPort(this.originalViewPort);
    final pictureViewPort = tryParseViewPort(this.pictureViewPort);
    if (originalViewPort != null && pictureViewPort != null) {
      final width = max(originalViewPort.width, pictureViewPort.width);
      final height = max(originalViewPort.height, pictureViewPort.height);
      return width / height;
    } else {
      final width = this.width;
      final height = this.height;
      return width == null || height == null ? null : width / height;
    }
  }

  static Rectangle? tryParseViewPort(String? str) {
    final values = str?.split(RegExp(r'[\s,;]'))
        .map(double.tryParse)
        .whereType<double>()
        .toList();
    if (values == null || values.length != 4) {
      return null;
    }
    return Rectangle(values[0], values[1], values[2], values[3]);
  }

  factory Record.fromJson(Map<String, dynamic> json) => _$RecordFromJson(json);

  Map<String, dynamic> toJson() => _$RecordToJson(this);
}

extension RecordRepository on Repository<Record> {
  Future<List<Record>> findRecordsWithPictures(List<int> pictureIds) async {
    final finder = Finder(
      filter: Filter.or([
        Filter.inList('originalId', pictureIds),
        Filter.inList('pictureId', pictureIds),
      ]),
    );
    final result = await find(finder);
    return result;
  }
}
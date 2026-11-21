import 'package:json_annotation/json_annotation.dart';

class DateTimeConverter implements JsonConverter<DateTime, Object> {
  const DateTimeConverter();

  @override
  DateTime fromJson(Object obj) {
    if (obj is int) {
      return DateTime.fromMillisecondsSinceEpoch(obj);
    }
    return DateTime.parse(obj.toString());
  }

  @override
  Object toJson(DateTime date) => date.millisecondsSinceEpoch;
}
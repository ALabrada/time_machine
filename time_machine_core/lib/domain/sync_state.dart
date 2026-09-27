import 'package:json_annotation/json_annotation.dart';

import 'date_time_converter.dart';

part 'sync_state.g.dart';

@JsonSerializable()
class SyncState {
  SyncState({
    required this.cloudId,
    required this.lastSync,
    this.localId,
  });

  @JsonKey(includeToJson: false, includeFromJson: false)
  int? localId;
  String cloudId;
  @DateTimeConverter()
  DateTime lastSync;

  factory SyncState.fromJson(Map<String, dynamic> json) => _$SyncStateFromJson(json);

  Map<String, dynamic> toJson() => _$SyncStateToJson(this);
}
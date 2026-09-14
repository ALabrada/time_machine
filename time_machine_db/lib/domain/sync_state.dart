import 'package:time_machine_db/time_machine_db.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:sembast/sembast.dart';

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

extension SyncStateRepository on Repository<SyncState> {
  Future<SyncState?> findByCloudId(String cloudId) async {
    final finder = Finder(filter: Filter.equals('cloudId', cloudId), limit: 1);
    final result = await findFirst(finder);
    return result;
  }
}
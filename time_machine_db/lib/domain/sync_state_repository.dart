import 'package:sembast/sembast.dart';
import 'package:time_machine_core/domain/sync_state.dart';

import '../services/repository.dart';

extension SyncStateRepository on Repository<SyncState> {
  Future<SyncState?> findByCloudId(String cloudId) async {
    final finder = Finder(filter: Filter.equals('cloudId', cloudId), limit: 1);
    final result = await findFirst(finder);
    return result;
  }
}
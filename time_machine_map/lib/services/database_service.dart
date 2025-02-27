import 'package:time_machine_db/time_machine_db.dart';

extension MapDatabaseService on DatabaseService {
  Future<Picture> savePicture(Picture model) async {
    final repo = createRepository<Picture>();
    return await repo.upsert(model);
  }
}
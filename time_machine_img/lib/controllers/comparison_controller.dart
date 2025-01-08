import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/time_machine_net.dart';
import 'package:path/path.dart' as p;

class ComparisonController {
  ComparisonController({
    this.databaseService,
    this.networkService,
    this.record,
  });

  final DatabaseService? databaseService;
  final NetworkService? networkService;
  Record? record;

  Future<Record?> loadRecord(int? id) async {
    if (id == null) {
      return null;
    }
    final record = await databaseService?.createRepository<Record>().getById(id);
    if (record == null) {
      return null;
    }

    this.record = record;
    record.picture = await databaseService?.createRepository<Picture>().getById(record.pictureId);

    final originalId = record.originalId;
    if (originalId != null) {
      record.original = await databaseService?.createRepository<Picture>().getById(originalId);
    }

    return record;
  }

  Future<bool> removeRecord() async {
    final record = this.record;
    final recordId = record?.localId;
    final db = databaseService;
    if (record == null || recordId == null || db == null) {
      return false;
    }

    if (!await db.createRepository<Record>().delete(recordId)) {
      return false;
    }

    if (!await db.createRepository<Picture>().delete(record.pictureId)) {
      return false;
    }

    final url = Uri.tryParse(record.picture?.url ?? '');
    if (url != null) {
      await File(url.path).delete();
    }

    return true;
  }

  Future<void> sharePictures() async {
    final record = this.record;
    final picture = record?.picture;
    if (record == null || picture == null) {
      return;
    }

    await Share.shareXFiles([
      XFile(Uri.parse(picture.url).path),
      if (record.original != null)
        await _download(record.original!),
    ], text: picture.description);
  }

  Future<XFile> _download(Picture picture) async {
    if (networkService == null) {
      throw Exception('No network service');
    }
    final dirPath = await getTemporaryDirectory();
    final path = p.join(dirPath.path, 'picture.jpg');
    await networkService?.download(picture.url, path);
    return XFile(path);
  }
}
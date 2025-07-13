import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_img/services/database_service.dart';
import 'package:time_machine_net/time_machine_net.dart';

class PictureController {
  PictureController({
    this.cacheManager,
    this.databaseService,
    this.networkService,
    this.picture,
  });

  final BaseCacheManager? cacheManager;
  final DatabaseService? databaseService;
  final NetworkService? networkService;
  Picture? picture;

  Future<Picture?> loadPicture(int? id) async {
    if (id == null) {
      return null;
    }
    picture = await databaseService?.loadPicture(id);
    return picture;
  }

  Future<void> sharePicture() async {
    final picture = this.picture;
    if (picture == null) {
      return;
    }

    final cache = cacheManager ?? DefaultCacheManager();
    final file = await cache.getSingleFile(picture.url);

    await Share.shareXFiles([
      XFile(file.path),
    ], text: picture.text);
  }
}
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/time_machine_net.dart';
import 'package:path/path.dart' as p;

class PictureController {
  PictureController({
    this.databaseService,
    this.networkService,
    this.picture,
  });

  final DatabaseService? databaseService;
  final NetworkService? networkService;
  Picture? picture;

  Future<Picture?> loadPicture(int? id) async {
    if (id == null) {
      return null;
    }
    picture = await databaseService?.createRepository<Picture>().getById(id);
    return picture;
  }

  Future<void> sharePicture() async {
    final picture = this.picture;
    if (picture == null) {
      return;
    }

    final dirPath = await getTemporaryDirectory();
    final path = p.join(dirPath.path, 'picture.jpg');
    await networkService?.download(picture.url, path);

    await Share.shareXFiles([
      XFile(path),
    ], text: picture.text);
  }
}
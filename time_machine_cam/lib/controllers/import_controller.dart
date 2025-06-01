import 'package:image_picker/image_picker.dart';
import 'package:time_machine_cam/services/database_service.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/time_machine_net.dart';

class ImportController {
  ImportController({
    this.configurationService,
    this.databaseService,
    this.networkService,
    this.original,
    this.picture,
  });

  final ConfigurationService? configurationService;
  final DatabaseService? databaseService;
  final NetworkService? networkService;
  Picture? original, picture;

  double get pictureOpacity => configurationService?.cameraPictureOpacity ?? ConfigurationService.defaultCameraPictureOpacity;

  Future<Picture?> loadPicture(int? id) async {
    if (id == null) {
      return null;
    }
    original = await databaseService?.createRepository<Picture>().getById(id);
    return original;
  }

  Future<Picture?> importPicture() async {
    if (picture != null) {
      return picture;
    }
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (file == null) {
      return null;
    }
    picture = await databaseService?.createPicture(file: file);
    return picture;
  }
}
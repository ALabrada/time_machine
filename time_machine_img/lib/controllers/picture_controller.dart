import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'package:share_plus/share_plus.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_img/services/database_service.dart';
import 'package:time_machine_net/time_machine_net.dart';

/// Keeps the [Picture] rendered by [PicturePage] in sync with the database,
/// reacting to changes pushed by [CloudSyncService] as well as to local writes
/// observed through [DatabaseService.events]. Only [Picture]s are watched here
/// — record pages use `SyncRecordController`.
///
/// The page renders from [pictureChanges] (initial load + every content
/// change). The picture is re-read with raw `getById`, so `visitedAt` — which
/// itself emits an `EntityUpdated` event — never produces a feedback loop;
/// only a description change is published. When the picture disappears
/// [entityDeleted] fires once and the page navigates away.
class PictureController {
  PictureController({
    required this.cacheService,
    this.databaseService,
    this.networkService,
    this.cloudSyncService,
    this.picture,
  });

  final CacheService cacheService;
  final DatabaseService? databaseService;
  final NetworkService? networkService;
  final CloudSyncService? cloudSyncService;
  Picture? picture;

  final _pictureChanges = BehaviorSubject<Picture?>();
  final _deletedController = StreamController<void>.broadcast();
  StreamSubscription<void>? _dbUpdatedSubscription;
  StreamSubscription<RepositoryEvent>? _eventsSubscription;
  bool _hasPicture = false;
  bool _deleted = false;

  /// Emits the watched picture — first load and every content change. The
  /// description fingerprint is applied with `distinct`, so pictures whose
  /// description did not change are never re-published.
  Stream<Picture?> get pictureChanges => _pictureChanges.stream.distinct(
    (previous, next) => previous?.description == next?.description,
  );

  /// Emits once when the watched picture no longer exists.
  Stream<void> get entityDeleted => _deletedController.stream;

  /// Starts monitoring [id] and kicks off the first load.
  void watchPicture(int? id) {
    if (id == null) {
      return;
    }
    _dbUpdatedSubscription?.cancel();
    _dbUpdatedSubscription = cloudSyncService?.dbUpdated.listen((_) {
      unawaited(_reload(id));
    });
    _eventsSubscription?.cancel();
    _eventsSubscription = databaseService?.events.listen((event) {
      if (event is EntityUpdated<Picture> && event.entity.localId == id) {
        unawaited(_reload(id));
      }
    });
    unawaited(_reload(id));
  }

  Future<void> _reload(int id) async {
    if (_deleted) {
      return;
    }
    final picture = await databaseService?.createRepository<Picture>().getById(id);
    if (_deleted) {
      return;
    }
    if (picture == null) {
      if (_hasPicture) {
        _deleted = true;
        _deletedController.add(null);
      }
      return;
    }
    _hasPicture = true;
    this.picture = picture;
    _pictureChanges.add(picture);
  }

  void dispose() {
    _dbUpdatedSubscription?.cancel();
    _eventsSubscription?.cancel();
    _deletedController.close();
    _pictureChanges.close();
  }

  Future<void> sharePicture() async {
    final picture = this.picture;
    if (picture == null) {
      return;
    }

    final file = await cacheService.fetch(picture.url);

    await SharePlus.instance.share(ShareParams(
      files: [file],
      text: picture.text,
    ));
  }

  Future<void> updateDescription(String description) async {
    final picture = this.picture;
    if (picture == null) {
      return;
    }
    picture.description = description.isEmpty ? null : description;
    await databaseService?.savePicture(picture);
  }
}
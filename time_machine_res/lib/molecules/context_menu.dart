import 'package:adaptive_action_sheet/adaptive_action_sheet.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_res/l10n/res_localizations.dart';

extension ContextMenu on BuildContext {
  Future<void> showContextMenu({
    required Picture model,
    required Function (String uri) navigateTo,
    required Function (String uri) shareFile,
    DatabaseService? databaseService,
  }) async {
    final title = model.description;
    final site = model.site;
    await showAdaptiveActionSheet<Picture>(
      context: this,
      title: title == null ? null : Text(title),
      cancelAction: CancelAction(
        title: Text(ResLocalizations.of(this).menuActionCancel),
      ),
      actions: [
        BottomSheetAction(
          leading: Icon(Icons.open_in_full),
          title: Text(ResLocalizations.of(this).menuActionView),
          onPressed: (context) {
            databaseService?.savePicture(model).then((id) {
              navigateTo('/picture/$id');
            });
            Navigator.of(context).pop();
          },
        ),
        BottomSheetAction(
          leading: Icon(Icons.photo_library),
          title: Text(ResLocalizations.of(this).menuActionImport),
          onPressed: (context) {
            databaseService?.savePicture(model).then((id) {
              navigateTo('/import?pictureId=$id');
            });
            Navigator.of(context).pop();
          },
        ),
        BottomSheetAction(
          leading: Icon(Icons.camera_alt),
          title: Text(ResLocalizations.of(this).menuActionCamera),
          onPressed: (context) {
            databaseService?.savePicture(model).then((id) {
              navigateTo('/camera?pictureId=$id');
            });
            Navigator.of(context).pop();
          },
        ),
        if (site != null && site.isNotEmpty)
          BottomSheetAction(
            leading: Icon(Icons.open_in_browser),
            title: Text(ResLocalizations.of(this).menuActionOpenSource),
            onPressed: (context) {
              navigateTo(site);
              Navigator.of(context).pop();
            },
          ),
        if (!kIsWeb)
          BottomSheetAction(
            leading: Icon(Icons.share),
            title: Text(ResLocalizations.of(this).menuActionShare),
            onPressed: (context) {
              final uri = Uri.parse(model.url);
              if (uri.isScheme('file')) {
                final path = databaseService?.expandPath(uri.path) ?? uri.path;
                shareFile(path);
              } else {
                CachedNetworkImageProvider.defaultCacheManager.getSingleFile(model.url).then((v) {
                  shareFile(v.path);
                });
              }
              Navigator.of(context).pop();
            },
          ),
      ],
    );
  }
}

extension _ResDatabaseService on DatabaseService {
  Future<int> savePicture(Picture model) async {
    final repo = createRepository<Picture>();
    final newModel = await repo.upsert(model);
    return newModel.localId!;
  }
}
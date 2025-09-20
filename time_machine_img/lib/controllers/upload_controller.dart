import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/time_machine_net.dart';

final class UploadController extends ChangeNotifier {
  static const defaultPageUrl = 'https://www.re.photos/en/compilation/create/';

  UploadController({
    required this.cacheService,
    this.databaseService,
    this.networkService,
    this.preferences,
    this.record,
    this.onUploadFile,
    this.onError,
    Uri? url,
  }) : url = url ?? Uri.parse(defaultPageUrl);

  final Uri url;
  final CacheService cacheService;
  final DatabaseService? databaseService;
  final NetworkService? networkService;
  final SharedPreferencesWithCache? preferences;
  final FutureOr<(Picture picture, bool align)?> Function()? onUploadFile;
  final void Function(String? description)? onError;

  final BehaviorSubject<int?> loadingProgress = BehaviorSubject();
  InAppWebViewController? webViewController;

  Record? record;
  String get baseUrl => Uri(
    scheme: url.scheme,
    host: url.host,
    port: url.port,
  ).toString();

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

  Future<void> loadCookies() async {
    final key = Uri.encodeComponent(baseUrl);
    final cookies = preferences?.getStringList('web.cookies.$key') ?? [];
    debugPrint('[WEB] loadCookies: $cookies');

    final manager = CookieManager.instance();
    await manager.deleteAllCookies();
    for (final value in cookies) {
      final cookie = Cookie.fromMap(jsonDecode(value));
      if (cookie != null) {
        manager.setCookie(url: WebUri(baseUrl), name: cookie.name, value: cookie.value);
      }
    }
  }

  Future<void> loadPage() async {
    await loadCookies();
  }

  Future<void> saveCookies() async {
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri(baseUrl),
    );
    final key = Uri.encodeComponent(baseUrl);
    final value = List.generate(cookies.length, (i) => jsonEncode(cookies[i].toJson()));
    preferences?.setStringList('web.cookies.$key', value);
    debugPrint('[WEB] saveCookies: $value');
  }

  Future<String?> showUploadMenu() async {
    final result = await onUploadFile?.call();
    if (result == null) {
      return null;
    }
    final (picture, align) = result;
    final url = Uri.tryParse(picture.url);
    if (picture.url.isEmpty || url == null || url.isScheme('file')) {
      return picture.url;
    }

    final file = await cacheService.fetch(picture.url);

    if (!align) {
      return Uri.file(file.path).toString();
    }

    return await _cropPicture(
      picture: picture,
      path: file.path,
    ) ?? Uri.file(file.path).toString();
  }

  Future<void> fillPage(String url) async {
    final record = this.record;
    final original = record?.original;
    final picture = record?.picture;
    if (record == null || original == null || picture == null) {
      return;
    }
    if (url == defaultPageUrl) {
      final title = original.description;
      if (title != null) {
        await _setInputFields({
          'id_upload-working_title': title,
        });
      }
    } else if (url.startsWith(defaultPageUrl)) {
      final title = original.description;
      final address = picture.description;
      final originalTime = original.time?.split('-') ?? [];
      final ownTime = picture.time?.split('-') ?? [];
      final lat = picture.latitude;
      final lng = picture.longitude;

      await _setInputFields({
        if (title != null && Intl.systemLocale.startsWith('en'))
          'id_metadata-title_en': title
        else if (title != null)
          'id_metadata-title_other': title,
        if (originalTime.isNotEmpty)
          'id_metadata-before_creation_year': originalTime[0],
        if (originalTime.length > 1)
          'id_metadata-before_creation_month': originalTime[1],
        if (originalTime.length > 2)
          'id_metadata-before_creation_day': originalTime[2],
        'id_metadata-before_creation_approximate': 'true',
        if (ownTime.isNotEmpty)
          'id_metadata-after_creation_year': ownTime[0],
        if (ownTime.length > 1)
          'id_metadata-after_creation_month': ownTime[1],
        if (ownTime.length > 2)
          'id_metadata-after_creation_day': ownTime[2],
        'id_metadata-position_latitude': lat.toStringAsFixed(6),
        'id_metadata-position_longitude': lng.toStringAsFixed(6),
        if (address != null)
          'id_metadata-location_text': address,
      });
    }
  }

  Future<String?> _cropPicture({
    required Picture picture,
    required String path,
  }) async {
    final record = this.record;
    if (record == null) {
      return null;
    }

    final originalViewPort = Record.tryParseViewPort(record.originalViewPort);
    final pictureViewPort = Record.tryParseViewPort(record.pictureViewPort);
    if (originalViewPort == null || pictureViewPort == null) {
      return null;
    }

    final intersection = originalViewPort.intersection(pictureViewPort);
    if (intersection == null) {
      return null;
    }

    Rectangle? viewPort;
    if (picture == record.picture && record.pictureViewPort != null) {
      viewPort = pictureViewPort;
    } else if (picture == record.original && record.originalViewPort != null) {
      viewPort = originalViewPort;
    } else {
      return null;
    }

    var image = await img.decodeImageFile(path);
    if (image == null) {
      return null;
    }

    final rect = cropImage(
      width: image.width,
      height: image.height,
      viewPort: viewPort,
      intersection: intersection,
    );
    image = await Future.microtask(() => img.copyCrop(image!,
      x: rect.left,
      y: rect.top,
      width: rect.width,
      height: rect.height,
    ));

    final dirPath = await getTemporaryDirectory();
    final dstPath = p.join(dirPath.path, 'pictures', '${picture.id}.jpg');
    if (!await img.encodeJpgFile(dstPath, image)) {
      return null;
    }

    return Uri.file(dstPath).toString();
  }

  void onPageStarted(String? url) {
    debugPrint('[WEB] load: $url');
    loadingProgress.value = 0;
  }

  void onPageFinished(String? url) {
    debugPrint('[WEB] loaded: $url');
    loadingProgress.value = null;
    unawaited(saveCookies());
    if (url != null) {
      unawaited(fillPage(url));
    }
  }

  void onHttpError() {
    debugPrint('[WEB] error}');
    onError?.call(null);
  }

  void onResourceError(WebResourceError error) {
    debugPrint('[WEB] error ${error.type}: ${error.description}');
    onError?.call(error.description);
  }

  Future<void> _setInputFields(Map<String, String> fieldValues) async {
    final script = [
      for (final e in fieldValues.entries)
        'document.getElementById("${e.key}").value = "${e.value.replaceAll('"', '\\"')}";'
    ].join('\n');
    await webViewController?.evaluateJavascript(source: script);
  }

  FutureOr<NavigationActionPolicy> onNavigationRequest(NavigationAction action) async {
    final url = action.request.url?.rawValue;
    if (url != null && !url.startsWith(baseUrl)) {
      debugPrint('[WEB] deny $url');
      return NavigationActionPolicy.CANCEL;
    }
    return NavigationActionPolicy.ALLOW;
  }

  Future<ShowFileChooserResponse> pickFile(ShowFileChooserRequest params) async {
    try {
      if (params.mode == ShowFileChooserRequestMode.OPEN) {
        final url = await showUploadMenu();
        if (url == null) {
          return ShowFileChooserResponse(handledByClient: true);
        }
        if (url.isNotEmpty) {
          return ShowFileChooserResponse(filePaths: [url], handledByClient: true);
        }
      }

      // If the input accepts images and has a capture attribute, open the camera.
      if (params.acceptTypes.any((type) => type == 'image/*') &&
          params.mode == ShowFileChooserRequestMode.OPEN) {
        final picker = ImagePicker();
        final photo = await picker.pickImage(source: ImageSource.camera);
        if (photo == null) return ShowFileChooserResponse(handledByClient: true);
        return ShowFileChooserResponse(
          filePaths: [Uri.file(photo.path).toString()],
          handledByClient: true,
        );
      }
      // If the input accepts video, allow video recording.
      else if (params.acceptTypes.any((type) => type == 'video/*') &&
          params.mode == ShowFileChooserRequestMode.OPEN) {
        final picker = ImagePicker();
        final video = await picker.pickVideo(
            source: ImageSource.camera,
            maxDuration: const Duration(seconds: 10));
        if (video == null) return ShowFileChooserResponse(handledByClient: true);
        return ShowFileChooserResponse(
          filePaths: [Uri.file(video.path).toString()],
          handledByClient: true,
        );
      }
      // For general file picking, use the FilePicker package.
      else if (params.mode == ShowFileChooserRequestMode.OPEN_MULTIPLE) {
        final result = await FilePicker.platform.pickFiles(allowMultiple: true);
        if (result == null) return ShowFileChooserResponse(handledByClient: true);
        final files = result.files
            .where((file) => file.path != null)
            .map((file) => Uri.file(file.path!).toString())
            .toList();
        return ShowFileChooserResponse(filePaths: files, handledByClient: true);
      } else {
        final result = await FilePicker.platform.pickFiles();
        if (result == null) return ShowFileChooserResponse(handledByClient: true);
        return ShowFileChooserResponse(
          filePaths: [Uri.file(result.files.single.path!).toString()],
          handledByClient: true,
        );
      }
    } catch (e) {
      onError?.call(e.toString());
      return ShowFileChooserResponse(handledByClient: true);
    }
  }
}
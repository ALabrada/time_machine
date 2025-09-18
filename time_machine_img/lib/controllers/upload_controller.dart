import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/time_machine_net.dart';
import 'package:webview_cookie_manager_plus/webview_cookie_manager_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

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
  }) : url = url ?? Uri.parse(defaultPageUrl) {
    webViewController.setNavigationDelegate(
      NavigationDelegate(
        onProgress: (int progress) {
          if (loadingProgress.valueOrNull != null) {
            loadingProgress.value = progress;
          }
        },
        onPageStarted: _onPageStarted,
        onPageFinished: _onPageFinished,
        onHttpError: _onHttpError,
        onWebResourceError: _onResourceError,
        onNavigationRequest: _onNavigationRequest,
      )
    );
  }

  final Uri url;
  final CacheService cacheService;
  final DatabaseService? databaseService;
  final NetworkService? networkService;
  final SharedPreferencesWithCache? preferences;
  final WebViewController webViewController = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted);
  final FutureOr<(Picture picture, bool align)?> Function()? onUploadFile;
  final void Function(String? description)? onError;

  final BehaviorSubject<int?> loadingProgress = BehaviorSubject();

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

    final manager = WebviewCookieManager();
    await manager.clearCookies();
    await manager.setCookies([
      for (final value in cookies)
        Cookie.fromSetCookieValue(value),
    ], origin: baseUrl);
  }

  Future<void> loadPage() async {
    if (Platform.isAndroid) {
      final androidController = webViewController.platform as AndroidWebViewController;
      await androidController.setOnShowFileSelector(_androidFilePicker);
    }

    await loadCookies();
    await webViewController.loadRequest(url);
  }

  Future<void> saveCookies() async {
    final cookies = await WebviewCookieManager().getCookies(baseUrl);
    final key = Uri.encodeComponent(baseUrl);
    final value = List.generate(cookies.length, (i) => cookies[i].toString());
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

  void _onPageStarted(String url) {
    debugPrint('[WEB] load: $url');
    loadingProgress.value = 0;
  }

  void _onPageFinished(String url) {
    debugPrint('[WEB] loaded: $url');
    loadingProgress.value = null;
    unawaited(saveCookies());
    unawaited(fillPage(url));
  }

  void _onHttpError(HttpResponseError error) {
    debugPrint('[WEB] error: ${error.response?.toString()}');
    onError?.call(null);
  }

  void _onResourceError(WebResourceError error) {
    debugPrint('[WEB] error ${error.errorCode}: ${error.description}');
    onError?.call(error.description);
  }

  Future<void> _setInputFields(Map<String, String> fieldValues) async {
    final script = [
      for (final e in fieldValues.entries)
        'document.getElementById("${e.key}").value = "${e.value.replaceAll('"', '\\"')}";'
    ].join('\n');
    await webViewController.runJavaScript(script);
  }

  FutureOr<NavigationDecision> _onNavigationRequest(NavigationRequest request) async {
    if (!request.url.startsWith(baseUrl)) {
      debugPrint('[WEB] deny ${request.url}');
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  Future<List<String>> _androidFilePicker(FileSelectorParams params) async {
    try {
      if (params.mode == FileSelectorMode.open) {
        final url = await showUploadMenu();
        if (url == null) {
          return [];
        }
        if (url.isNotEmpty) {
          return [url];
        }
      }

      // If the input accepts images and has a capture attribute, open the camera.
      if (params.acceptTypes.any((type) => type == 'image/*') &&
          params.mode == FileSelectorMode.open) {
        final picker = ImagePicker();
        final photo = await picker.pickImage(source: ImageSource.camera);
        if (photo == null) return [];
        return [Uri.file(photo.path).toString()];
      }
      // If the input accepts video, allow video recording.
      else if (params.acceptTypes.any((type) => type == 'video/*') &&
          params.mode == FileSelectorMode.open) {
        final picker = ImagePicker();
        final video = await picker.pickVideo(
            source: ImageSource.camera,
            maxDuration: const Duration(seconds: 10));
        if (video == null) return [];
        return [Uri.file(video.path).toString()];
      }
      // For general file picking, use the FilePicker package.
      else if (params.mode == FileSelectorMode.openMultiple) {
        final result = await FilePicker.platform.pickFiles(allowMultiple: true);
        if (result == null) return [];
        return result.files
            .where((file) => file.path != null)
            .map((file) => Uri.file(file.path!).toString())
            .toList();
      } else {
        final result = await FilePicker.platform.pickFiles();
        if (result == null) return [];
        return [Uri.file(result.files.single.path!).toString()];
      }
    } catch (e) {
      onError?.call(e.toString());
      return [];
    }
  }
}
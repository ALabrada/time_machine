import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
    this.databaseService,
    this.networkService,
    this.preferences,
    this.record,
    this.onUploadFile,
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
  final DatabaseService? databaseService;
  final NetworkService? networkService;
  final SharedPreferencesWithCache? preferences;
  final WebViewController webViewController = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted);
  final FutureOr<Picture?> Function()? onUploadFile;

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
    final picture = await onUploadFile?.call();
    if (picture == null) {
      return null;
    }
    final url = Uri.tryParse(picture.url);
    if (url == null || url.isScheme('file')) {
      return picture.url;
    }

    final networkService = this.networkService;
    if (networkService == null) {
      throw Exception('No network service');
    }
    final dirPath = await getTemporaryDirectory();
    final path = p.join(dirPath.path, 'picture.jpg');
    await networkService.download(picture.url, path);
    return Uri.file(path).toString();
  }

  void _onPageStarted(String url) {
    debugPrint('[WEB] load: $url');
    loadingProgress.value = 0;
  }

  void _onPageFinished(String url) {
    debugPrint('[WEB] loaded: $url');
    loadingProgress.value = null;
    unawaited(saveCookies());
  }

  void _onHttpError(HttpResponseError error) {
    debugPrint('[WEB] error: ${error.response?.toString()}');
  }

  void _onResourceError(WebResourceError error) {
    debugPrint('[WEB] error ${error.errorCode}: ${error.description}');
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
        if (url != null) {
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
      return [];
    }
  }
}
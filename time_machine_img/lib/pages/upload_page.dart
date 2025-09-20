import 'dart:async';

import 'package:adaptive_action_sheet/adaptive_action_sheet.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_db/time_machine_db.dart';
import '../controllers/upload_controller.dart';
import '../l10n/img_localizations.dart';

class UploadPage extends StatefulWidget {
  const UploadPage({
    super.key,
    this.recordId,
    this.webPage='',
  });

  final int? recordId;
  final String webPage;

  @override
  _UploadPageState createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final settings = InAppWebViewSettings(
    isInspectable: kDebugMode,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    iframeAllowFullscreen: true,
    useShouldOverrideUrlLoading: true,
    useOnShowFileChooser: true,
  );
  final GlobalKey webViewKey = GlobalKey();
  late UploadController uploadController;

  @override
  void initState() {
    uploadController = UploadController(
      cacheService: context.read(),
      databaseService: context.read(),
      networkService: context.read(),
      preferences: context.read(),
      url: widget.webPage.isEmpty ? null : Uri.parse(widget.webPage),
      onUploadFile: () => showUploadMenu(),
      onError: _showError,
    );
    super.initState();
    unawaited(_loadPage());
  }

  Future<void> _loadPage() async {
    final record = await uploadController.loadRecord(widget.recordId);
    if (record == null) {
      return;
    }
    await uploadController.loadPage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildContent(),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: Text( ImgLocalizations.of(context).uploadPage(uploadController.url.host)),
      backgroundColor: Theme.of(context).colorScheme.secondary,
      foregroundColor: Theme.of(context).colorScheme.onSecondary,
    );
  }

  Widget _buildContent() {
    return Stack(
      children: [
        FutureBuilder(
          future: _loadPage(),
          builder: (context, _) {
            return InAppWebView(
              key: webViewKey,
              initialUrlRequest:
              URLRequest(url: WebUri.uri(uploadController.url)),
              initialSettings: settings,
              onWebViewCreated: (controller) {
                uploadController.webViewController = controller;
              },
              onLoadStart: (_, url) {
                uploadController.onPageStarted(url?.rawValue);
              },
              onPermissionRequest: (_, request) async {
                return PermissionResponse(
                  resources: request.resources,
                  action: PermissionResponseAction.GRANT,
                );
              },
              shouldOverrideUrlLoading: (_, navigationAction) async {
                return uploadController.onNavigationRequest(navigationAction);
              },
              onLoadStop: (_, url) async {
                uploadController.onPageFinished(url?.rawValue);
              },
              onReceivedError: (_, request, error) {
                uploadController.onResourceError(error);
              },
              onReceivedHttpError: (_, request, resource) {
                uploadController.onHttpError();
              },
              onShowFileChooser: (_, request) async {
                return uploadController.pickFile(request);
              },
              onConsoleMessage: (_, consoleMessage) {
                if (kDebugMode) {
                  print(consoleMessage);
                }
              },
            );
          },
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 4,
          child: StreamBuilder(
            stream: uploadController.loadingProgress,
            builder: (context, snapshot) {
              final percent = snapshot.data;
              return Visibility(
                visible: percent != null,
                child: LinearProgressIndicator(
                  value: (percent ?? 0).toDouble() / 100.0,
                  minHeight: 4,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<(Picture, bool)?> showUploadMenu() async {
    final record = uploadController.record;
    if (record == null) {
      return null;
    }
    final picture = record.picture;
    final original = record.original;
    return await showAdaptiveActionSheet<(Picture, bool)>(
      context: context,
      title: Text(ImgLocalizations.of(context).uploadMenu),
      cancelAction: CancelAction(
        title: Text(ImgLocalizations.of(context).uploadMenuCancel),
      ),
      actions: [
        if (picture != null)
          BottomSheetAction(
            title: Text(ImgLocalizations.of(context).uploadMenuPicture),
            onPressed: (context) {
              context.pop((picture, false));
            },
          ),
        if (picture != null && record.pictureViewPort != null)
          BottomSheetAction(
            title: Text(ImgLocalizations.of(context).uploadMenuPictureAligned),
            onPressed: (context) {
              context.pop((picture, true));
            },
          ),
        if (original != null)
          BottomSheetAction(
            title: Text(ImgLocalizations.of(context).uploadMenuOriginal),
            onPressed: (context) {
              context.pop((original, false));
            },
          ),
        if (original != null && record.originalViewPort != null)
          BottomSheetAction(
            title: Text(ImgLocalizations.of(context).uploadMenuOriginalAligned),
            onPressed: (context) {
              context.pop((original, true));
            },
          ),
        BottomSheetAction(
          title: Text(ImgLocalizations.of(context).uploadMenuFile),
          onPressed: (context) {
            context.pop((Picture(id: '', url: '', latitude: 0, longitude: 0), false));
          },
        ),
      ],
    );
  }

  void _showError(String? description) {
    if (!mounted) {
      return;
    }
    final text = description ?? ImgLocalizations.of(context).errorLoadingPage;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
    ));
  }
}

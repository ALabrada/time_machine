import 'dart:async';

import 'package:adaptive_action_sheet/adaptive_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:time_machine_db/time_machine_db.dart';
import '../controllers/upload_controller.dart';

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
  late UploadController uploadController;

  @override
  void initState() {
    uploadController = UploadController(
      databaseService: context.read(),
      networkService: context.read(),
      preferences: context.read(),
      url: widget.webPage.isEmpty ? null : Uri.parse(widget.webPage),
      onUploadFile: () => showUploadMenu(),
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
      title: Text("Upload to ${uploadController.url.host}"),
      backgroundColor: Theme.of(context).colorScheme.secondary,
      foregroundColor: Theme.of(context).colorScheme.onSecondary,
    );
  }

  Widget _buildContent() {
    return Stack(
      children: [
        WebViewWidget(
          controller: uploadController.webViewController,
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

  Future<Picture?> showUploadMenu() async {
    final record = uploadController.record;
    if (record == null) {
      return null;
    }
    final picture = record.picture;
    final original = record.original;
    return await showAdaptiveActionSheet<Picture>(
      context: context,
      title: const Text("What to upload?"),
      cancelAction: CancelAction(title: const Text('Other file')),
      actions: [
        if (picture != null)
          BottomSheetAction(
            title: const Text("My picture"),
            onPressed: (context) {
              context.pop(picture);
            },
          ),
        if (original != null)
          BottomSheetAction(
            title: const Text("Old picture"),
            onPressed: (context) {
              context.pop(original);
            },
          ),
      ],
    );
  }
}

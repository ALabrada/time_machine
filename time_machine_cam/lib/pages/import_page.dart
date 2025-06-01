import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cropperx/cropperx.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../controllers/import_controller.dart';

class ImportPage extends StatefulWidget {
  const ImportPage({
    super.key,
    this.pictureId,
  });

  final int? pictureId;

  @override
  _ImportPageState createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  final _cropperKey = GlobalKey(debugLabel: 'cropperKey');
  late ImportController controller;

  @override
  void initState() {
    controller = ImportController(
      configurationService: context.read(),
      databaseService: context.read(),
      networkService: context.read(),
    );
    super.initState();
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
      title: Text( ''),
      backgroundColor: Theme.of(context).colorScheme.secondary,
      foregroundColor: Theme.of(context).colorScheme.onSecondary,
    );
  }

  Widget _buildContent() {
    return Stack(
      children: [
        _buildCropper(),
        _buildOriginal(),
      ],
    );
  }

  Widget _buildOriginal() {
    return FutureBuilder(
      future: controller.loadPicture(widget.pictureId),
      builder: (context, snapshot) {
        final picture = snapshot.data;
        if (picture == null) {
          return SizedBox.shrink();
        }
        return IgnorePointer(
          child: Opacity(
            opacity: controller.pictureOpacity,
            child: CachedNetworkImage(
              imageUrl: picture.url,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCropper() {
    return FutureBuilder(
      future: ImagePicker().pickImage(source: ImageSource.gallery),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) {
          return SizedBox.shrink();
        }
        return Cropper(
          cropperKey: _cropperKey, // Use your key here
          image: Image.file(File(file.path)),
        );
      },
    );
  }
}

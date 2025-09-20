import 'dart:io';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:custom_image_crop/custom_image_crop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_cam/domain/image_painter.dart';
import 'package:time_machine_cam/l10n/cam_localizations.dart';
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
  late ImportController controller;

  @override
  void initState() {
    controller = ImportController(
      cacheService: context.read(),
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
      title: Text( CamLocalizations.of(context).importPage),
      backgroundColor: Theme.of(context).colorScheme.secondary,
      foregroundColor: Theme.of(context).colorScheme.onSecondary,
      actions: [
        StreamBuilder(
          stream: controller.isProcessing,
          initialData: false,
          builder: (context, snapshot) {
            if (snapshot.requireData) {
              return Center(
                heightFactor: 1,
                widthFactor: 1,
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(),
                ),
              );
            }
            return IconButton(
              onPressed: _savePicture,
              icon: Icon(Icons.done),
            );
          },
        ),
      ],
    );
  }

  Widget _buildContent() {
    return FutureBuilder(
      future: _init(),
      builder: (context, snapshot) {
        final original = snapshot.data?.$1;
        final imported = snapshot.data?.$2;
        if (imported == null || original == null) {
          return SizedBox.shrink();
        }

        CustomPaint drawPath(Path path, {
          Paint? pathPaint,
          Color outlineColor = Colors.white,
          double outlineStrokeWidth = 4.0,
        }) {
          return ImagePainter.create(
            image: original,
            imageOpacity: controller.pictureOpacity,
            path: path,
          );
        }

        return CustomImageCrop(
          shape: CustomCropShape.Ratio,
          ratio: Ratio(width: original.width.toDouble(), height: original.height.toDouble()),
          cropController: controller.cropController,
          drawPath: drawPath,
          image: imported,
        );
      },
    );
  }

  Future<(ui.Image? original, ImageProvider? imported)> _init() async {
    final original = await controller.loadPicture(widget.pictureId);
    final originalFile = original == null
        ? null
        : await controller.cacheService.fetch(original.url);
    final originalImage = originalFile == null
        ? null
        : await decodeImageFromList(await originalFile.readAsBytes());
    final selection = await controller.pickImage();
    if (selection == null) {
      return (originalImage, null);
    }
    if (kIsWeb) {
      return (originalImage, MemoryImage(await selection.readAsBytes()));
    }
    final importedFile = File(selection.path);
    return (originalImage, FileImage(importedFile));
  }

  Future<void> _savePicture() async {
    final screenSize = MediaQuery.sizeOf(context);
    final record = await controller.importPicture(
      width: screenSize.width,
      height: screenSize.height,
    ).onError((error, _) {
      return null;
    });
    if (!mounted) {
      return;
    }
    if (record != null) {
      context.go('/gallery/${record.localId}');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(CamLocalizations.of(context).couldNotImportPhoto),
      ));
    }
  }
}

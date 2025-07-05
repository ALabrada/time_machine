import 'dart:async';
import 'dart:io';
import 'package:adaptive_action_sheet/adaptive_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:group_grid_view/group_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_img/controllers/gallery_controller.dart';
import 'package:time_machine_img/l10n/img_localizations.dart';
import 'package:time_machine_img/molecules/gallery_cell.dart';
import 'package:time_machine_res/time_machine_res.dart';

import '../molecules/gallery_search_bar.dart';
import '../molecules/tool_bar.dart';

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  _GalleryPageState createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  late GalleryController galleryController;

  @override
  void initState() {
    galleryController = GalleryController(
      sharingService: context.read(),
    );
    super.initState();
  }

  @override
  void dispose() {
    galleryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          GallerySearchBar(
            controller: galleryController.searchController,
            hintText: ImgLocalizations.of(context).searchBarHint,
          ),
          Expanded(
            child: Stack(
              children: [
                _buildGrid(),
                PositionedDirectional(
                  bottom: 16,
                  end: 8,
                  child: _buildToolbar(),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return StreamBuilder(
      stream: CombineLatestStream.combine2(
          galleryController.isEditing,
          galleryController.selection,
          (editing, selection) => editing ? selection.length : null,
      ),
      initialData: null,
      builder: (context, snapshot) {
        final editingOpacity = snapshot.data != null ? 1.0 : 0.0;
        return Column(
          children: [
            AnimatedOpacity(
              opacity: editingOpacity,
              duration: Duration(milliseconds: 300),
              child: FloatingActionButton(
                heroTag: "cancel",
                shape: const CircleBorder(),
                onPressed: galleryController.cancelEditing,
                child: Icon(Icons.cancel_outlined),
              ),
            ),
            const SizedBox(height: 16),
            AnimatedOpacity(
              opacity: editingOpacity,
              duration: Duration(milliseconds: 300),
              child: FloatingActionButton(
                heroTag: "delete",
                shape: const CircleBorder(),
                onPressed: () {
                  unawaited(_deleteSelection());
                },
                child: Icon(Icons.delete_outline),
              ),
            ),
            const SizedBox(height: 22),
            AnimatedOpacity(
              opacity: editingOpacity,
              duration: Duration(milliseconds: 300),
              child: StreamBuilder(
                stream: galleryController.isProcessing,
                initialData: false,
                builder: (context, snapshot) {
                  if (snapshot.requireData) {
                    return SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(),
                    );
                  }
                  return FloatingActionButton(
                    heroTag: "export",
                    onPressed: () {
                      unawaited(galleryController.export(
                        dialogTitle: ImgLocalizations.of(context).shareMenuExport,
                      ));
                    },
                    child: Icon(Icons.archive_outlined),
                  );
                },
              ),
            ),
            const SizedBox(height: 22),
            FloatingActionButton(
              heroTag: "import",
              onPressed: () {
                unawaited(galleryController.importRecords(
                  databaseService: context.read(),
                ));
              },
              child: Icon(Icons.unarchive_outlined),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGrid() {
    return StreamBuilder(
      stream: galleryController.loadAndFilterElements(
        databaseService: context.watch(),
      ),
      builder: (context, snapshot) {
        final sections = snapshot.data;
        if (sections == null) {
          return Center(
            child: CircularProgressIndicator()
          );
        }
        if (sections.isEmpty) {
          final criteria = galleryController.searchController.text.trim();
          return Center(
            child: Text(criteria.isEmpty
                ? ImgLocalizations.of(context).galleryEmptyList
                : ImgLocalizations.of(context).galleryNoSearchResults,
              style: TextTheme.of(context).headlineMedium,
            ),
          );
        }
        return GroupGridView(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 0,
            crossAxisSpacing: 0,
          ),
          sectionCount: sections.length,
          headerForSection: (section) => Padding(
            padding: EdgeInsets.only(top: 8, bottom: 4),
            child: Text(sections[section].title,
              style: TextTheme.of(context).headlineSmall,
            ),
          ),
          itemInSectionCount: (section) => sections[section].elements.length,
          itemInSectionBuilder: (context, index) {
            return _buildCell(sections[index.section].elements[index.index]);
          },
        );
      },
    );
  }

  Widget _buildCell(Record record) {
    return FutureBuilder(
      future: galleryController.loadPicture(record.pictureId),
      builder: (context, snapshot) {
        final picture = snapshot.data;
        return StreamBuilder(
          stream: CombineLatestStream.combine2(
              galleryController.isEditing,
              galleryController.selection,
              (editing, selection) => editing ? selection.contains(record) : null
          ),
          builder: (context, snapshot) {
            final isSelected = snapshot.data;
            return GalleryCell(
              uri: picture == null ? null : Uri.tryParse(picture.url),
              isSelected: isSelected,
              onTap: () => _select(record),
              onLongPress: () => galleryController.toggleSelection(record),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteSelection() async {
    final confirm = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: Text(galleryController.selection.value.length == 1
              ? ImgLocalizations.of(context).deleteOneSubtitle
              : ImgLocalizations.of(context).deleteManySubtitle),
          children: [
            SimpleDialogOption(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: Text(ImgLocalizations.of(context).deleteConfirm,
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: Text(ImgLocalizations.of(context).deleteCancel),
            ),
          ],
        );
      },
    );
    if (confirm != true) {
      return;
    }

    await galleryController.removeRecords();
  }

  void _select(Record element) {
    if (galleryController.isEditing.value) {
      galleryController.toggleSelection(element);
    } else {
      context.go('/gallery/${element.localId}');
    }
  }
}

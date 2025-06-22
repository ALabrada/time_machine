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
                Positioned(
                  bottom: 40,
                  left: 40,
                  right: 40,
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
        final selection = snapshot.data ?? 0;
        return AnimatedOpacity(
          duration: Duration(milliseconds: 300),
          opacity: snapshot.data != null ? 1 : 0,
          child: ToolBar(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondary,
              borderRadius: BorderRadius.circular(100),
              boxShadow: [
                BoxShadow(
                  offset: Offset(0,2),
                  blurRadius: 10.0,
                  color: gray06.withValues(alpha: 0.5),
                ),
              ],
            ),
            children: [
              IconButton(
                onPressed: () {
                  unawaited(galleryController.importRecords(
                    databaseService: context.read(),
                  ));
                },
                icon: Icon(Icons.file_open),
              ),
              StreamBuilder(
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
                  return IconButton(
                    onPressed: selection == 0 ? null : () {
                      unawaited(galleryController.export(
                        dialogTitle: ImgLocalizations.of(context).shareMenuExport,
                      ));
                    },
                    icon: Icon(Icons.save_as),
                  );
                },
              ),
              IconButton(
                onPressed: selection == 0 ? null : () {
                  unawaited(_deleteSelection());
                },
                icon: Icon(Icons.delete),
              ),
              IconButton(
                onPressed: galleryController.cancelEditing,
                icon: Icon(Icons.cancel),
              ),
            ],
          ),
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

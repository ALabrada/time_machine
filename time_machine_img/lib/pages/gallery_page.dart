import 'dart:async';
import 'dart:io';
import 'package:adaptive_action_sheet/adaptive_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:group_grid_view/group_grid_view.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_img/controllers/gallery_controller.dart';
import 'package:time_machine_img/domain/gallery_section.dart';
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
          return _buildEmpty();
        }
        return GroupGridView(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 0,
            crossAxisSpacing: 0,
          ),
          sectionCount: sections.length,
          headerForSection: (section) => Padding(
            padding: EdgeInsets.only(top: 8, bottom: 4),
            child: _buildSectionHeader(sections[section]),
          ),
          itemInSectionCount: (section) => sections[section].length,
          itemInSectionBuilder: (context, index) {
            final section = sections[index.section];
            if (section is GroupedSection) {
              return _buildRecordCell(section.elements[index.index]);
            }
            if (section is RecentSection) {
              return _buildPictureCell(section.elements[index.index]);
            }
            return GalleryCell();
          },
        );
      },
    );
  }

  Widget _buildEmpty() {
    final criteria = galleryController.searchController.text.trim();
    if (criteria.isEmpty) {
      return Container(
        alignment: Alignment.center,
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ImgLocalizations.of(context).galleryEmptyListTitle,
              style: TextTheme.of(context).headlineMedium,
            ),
            SizedBox(height: 12),
            RichLocalization(
              text: ImgLocalizations.of(context).galleryEmptyListBody(Icons.unarchive_outlined.md, '/?tab=map', '/?tab=nearby'),
              textAlign: TextAlign.center,
              onTapLink: (_, href, __) {
                if (href != null) {
                  context.go(href);
                }
              },
            ),
          ],
        ),
      );
    }
    return Center(
      child: Text(ImgLocalizations.of(context).galleryNoSearchResults,
        style: TextTheme.of(context).headlineMedium,
      ),
    );
  }

  Widget _buildSectionHeader(GallerySection section) {
    final dateFormat = DateFormat.yMEd(ImgLocalizations.of(context).localeName);
    if (section is GroupedSection) {
      return Text(dateFormat.format(section.date),
        style: TextTheme.of(context).headlineSmall,
      );
    }
    return Text(ImgLocalizations.of(context).galleryRecentPictures,
      style: TextTheme.of(context).headlineSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildPictureCell(Picture? picture) {
    return GalleryCell(
      uri: picture == null ? null : Uri.tryParse(picture.url),
      onTap: picture == null ? null : () => _selectPicture(picture),
    );
  }

  Widget _buildRecordCell(Record record) {
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
              onTap: () => _selectRecord(record),
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

  void _selectRecord(Record element) {
    if (galleryController.isEditing.value) {
      galleryController.toggleSelection(element);
    } else {
      context.go('/gallery/${element.localId}');
    }
  }

  void _selectPicture(Picture element) {
    context.go('/picture/${element.localId}');
  }
}

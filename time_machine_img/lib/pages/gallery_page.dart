import 'dart:io';
import 'package:adaptive_action_sheet/adaptive_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:group_grid_view/group_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_img/controllers/gallery_controller.dart';
import 'package:time_machine_img/l10n/img_localizations.dart';
import 'package:time_machine_res/time_machine_res.dart';

import '../molecules/gallery_search_bar.dart';

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
          Expanded(child: _buildGrid()),
        ],
      ),
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
        return AspectRatio(
          aspectRatio: 1,
          child: picture == null ? null : InkWell(
            onTap: () => _select(record),
            child: Image.file(File.fromUri(Uri.parse(picture.url)),
              fit: BoxFit.cover,
            ),
          ),
        );
      },
    );
  }

  void _select(Record element) {
    context.go('/gallery/${element.localId}');
  }
}

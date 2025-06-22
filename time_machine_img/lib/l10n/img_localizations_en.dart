// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'img_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class ImgLocalizationsEn extends ImgLocalizations {
  ImgLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get deleteCancel => 'Cancel';

  @override
  String get deleteConfirm => 'Delete';

  @override
  String get deleteManySubtitle =>
      'Are you sure you want to delete the replicas?';

  @override
  String deleteManyTitle(Object count) {
    return 'Deleting $count';
  }

  @override
  String get deleteOneSubtitle =>
      'Are you sure you want to delete the replica?';

  @override
  String get deleteOneTitle => 'Deleting';

  @override
  String get errorLoadingPage => 'Could not connect to the server';

  @override
  String get comparisonPage => 'Comparison';

  @override
  String get comparisonBottom => 'Bottom';

  @override
  String get comparisonLeft => 'Left';

  @override
  String get comparisonMetric => 'Similarity';

  @override
  String get comparisonRight => 'Right';

  @override
  String get comparisonTop => 'Top';

  @override
  String get galleryEmptyList => 'The gallery is empty';

  @override
  String get galleryNoSearchResults => 'No search results';

  @override
  String get importError => 'Could not import the provided file';

  @override
  String get importSuccessful => 'File imported successfully';

  @override
  String get searchBarHint => 'Search...';

  @override
  String get shareMenu => 'How to share?';

  @override
  String get shareMenuCancel => 'Cancel';

  @override
  String get shareMenuExport => 'Export data';

  @override
  String get shareMenuImages => 'Share images';

  @override
  String shareMenuPublishTo(Object site) {
    return 'Publish in $site';
  }

  @override
  String shareMenuUploadTo(Object site) {
    return 'Upload to $site';
  }

  @override
  String get uploadMenu => 'What to upload?';

  @override
  String get uploadMenuCancel => 'Cancel';

  @override
  String get uploadMenuFile => 'Another file';

  @override
  String get uploadMenuFileAligned => 'Another file (Aligned)';

  @override
  String get uploadMenuOriginal => 'Old picture';

  @override
  String get uploadMenuOriginalAligned => 'Old picture (Aligned)';

  @override
  String get uploadMenuPicture => 'My picture';

  @override
  String get uploadMenuPictureAligned => 'My picture (Aligned)';

  @override
  String uploadPage(Object site) {
    return 'Upload to $site';
  }
}

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
  String get deleteTitle => 'Deleting';

  @override
  String get deleteSubtitle => 'Are you sure you want to delete the replica?';

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
  String get searchBarHint => 'Search...';

  @override
  String get shareMenu => 'How to share?';

  @override
  String get shareMenuCancel => 'Cancel';

  @override
  String get shareMenuImages => 'Share images';

  @override
  String shareMenuUploadTo(Object site) {
    return 'Upload to $site';
  }

  @override
  String get uploadMenu => 'What to upload?';

  @override
  String get uploadMenuFile => 'Another file';

  @override
  String get uploadMenuOriginal => 'Old picture';

  @override
  String get uploadMenuPicture => 'My picture';

  @override
  String uploadPage(Object site) {
    return 'Upload to $site';
  }
}

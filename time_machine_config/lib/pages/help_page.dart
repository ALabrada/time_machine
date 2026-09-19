import 'package:flutter/material.dart';
import 'package:time_machine_config/l10n/config_localizations.dart';
import 'package:time_machine_config/molecules/question_cell.dart';
import 'package:time_machine_res/time_machine_res.dart';

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  HelpPageState createState() => HelpPageState();
}

class HelpPageState extends State<HelpPage> {
  static const telegramChannel = 'https://t.me/history_lens_app';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildContent(),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: Text(ConfigLocalizations.of(context).helpPage),
      backgroundColor: Theme.of(context).colorScheme.secondary,
      foregroundColor: Theme.of(context).colorScheme.onSecondary,
    );
  }

  Widget _buildContent() {
    final isDesktop = isDesktopPlatform();
    final localizations = ConfigLocalizations.of(context);
    return ListView(
      children: [
        QuestionCell(
          key: ValueKey(1),
          title: localizations.questionWhatIsAppPurposeTitle,
          body: localizations.questionWhatIsAppPurposeBody(telegramChannel),
        ),
        QuestionCell(
          key: ValueKey(2),
          title: localizations.questionHowToFindPicturesTitle,
          body: isDesktop
              ? localizations.questionHowToFindPicturesBodyDesktop(
                  Icons.map.md, Icons.settings.md)
              : localizations.questionHowToFindPicturesBody(
                  Icons.radar.md, Icons.map.md, Icons.settings.md),
        ),
        QuestionCell(
          key: ValueKey(3),
          title: localizations.questionHowToReplicatePictureTitle,
          body: isDesktop
              ? localizations.questionHowToReplicatePictureBodyDesktop
              : localizations.questionHowToReplicatePictureBody,
        ),
        QuestionCell(
          key: ValueKey(4),
          title: localizations.questionHowToTakePictureTitle,
          body: isDesktop
              ? localizations.questionHowToTakePictureBodyDesktop
              : localizations.questionHowToTakePictureBody,
        ),
        QuestionCell(
          key: ValueKey(5),
          title: localizations.questionHowToImportPicturesTitle,
          body: localizations.questionHowToImportPicturesBody(Icons.done.md),
        ),
        QuestionCell(
          key: ValueKey(6),
          title: isDesktop
              ? localizations.questionHowToSharePicturesTitleDesktop
              : localizations.questionHowToSharePicturesTitle,
          body: isDesktop
              ? localizations.questionHowToSharePicturesBodyDesktop(
                  telegramChannel, Icons.open_in_browser.md)
              : localizations.questionHowToSharePicturesBody(
                  telegramChannel, Icons.open_in_browser.md),
        ),
        QuestionCell(
          key: ValueKey(7),
          title: localizations.questionWhatDataIsCollectedTitle,
          body: localizations.questionWhatDataIsCollectedBody,
        ),
      ],
    );
  }
}

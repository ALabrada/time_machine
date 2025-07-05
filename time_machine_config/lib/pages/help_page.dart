import 'dart:convert';

import 'package:expandable/expandable.dart';
import 'package:flutter/material.dart';
import 'package:time_machine_config/l10n/config_localizations.dart';
import 'package:time_machine_config/molecules/question_cell.dart';
import 'package:time_machine_res/time_machine_res.dart';

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  _HelpPageState createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
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
    return ListView(
      children: [
        QuestionCell(
          key: ValueKey(1),
          title: ConfigLocalizations.of(context).questionWhatIsAppPurposeTitle,
          body: ConfigLocalizations.of(context).questionWhatIsAppPurposeBody(telegramChannel),
        ),
        QuestionCell(
          key: ValueKey(2),
          title: ConfigLocalizations.of(context).questionHowToFindPicturesTitle,
          body: ConfigLocalizations.of(context).questionHowToFindPicturesBody(Icons.radar.md, Icons.map.md, Icons.settings.md),
        ),
        QuestionCell(
          key: ValueKey(3),
          title: ConfigLocalizations.of(context).questionHowToReplicatePictureTitle,
          body: ConfigLocalizations.of(context).questionHowToReplicatePictureBody,
        ),
        QuestionCell(
          key: ValueKey(4),
          title: ConfigLocalizations.of(context).questionHowToTakePictureTitle,
          body: ConfigLocalizations.of(context).questionHowToTakePictureBody,
        ),
        QuestionCell(
          key: ValueKey(5),
          title: ConfigLocalizations.of(context).questionHowToImportPicturesTitle,
          body: ConfigLocalizations.of(context).questionHowToImportPicturesBody(Icons.done.md),
        ),
        QuestionCell(
          key: ValueKey(6),
          title: ConfigLocalizations.of(context).questionHowToSharePicturesTitle,
          body: ConfigLocalizations.of(context).questionHowToSharePicturesBody(telegramChannel, Icons.open_in_browser.md),
        ),
        QuestionCell(
          key: ValueKey(7),
          title: ConfigLocalizations.of(context).questionWhatDataIsCollectedTitle,
          body: ConfigLocalizations.of(context).questionWhatDataIsCollectedBody,
        ),
      ],
    );
  }
}

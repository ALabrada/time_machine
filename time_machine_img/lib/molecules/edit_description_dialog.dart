import 'package:flutter/material.dart';

import '../l10n/img_localizations.dart';

class EditDescriptionDialog extends StatefulWidget {
  const EditDescriptionDialog({
    super.key,
    this.initialDescription,
  });

  final String? initialDescription;

  @override
  EditDescriptionDialogState createState() => EditDescriptionDialogState();
}

class EditDescriptionDialogState extends State<EditDescriptionDialog> {
  late final TextEditingController textController;

  @override
  void initState() {
    textController = TextEditingController(text: widget.initialDescription ?? '');
    super.initState();
  }

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ImgLocalizations.of(context);
    return AlertDialog(
      title: Text(strings.editDescriptionTitle),
      content: TextField(
        controller: textController,
        autofocus: true,
        maxLines: null,
        decoration: InputDecoration(
          hintText: strings.editDescriptionHint,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.deleteCancel),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: textController,
          builder: (context, value, _) {
            return TextButton(
              onPressed: value.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(textController.text),
              child: Text(strings.editDescriptionSave),
            );
          },
        ),
      ],
    );
  }
}
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:time_machine_img/l10n/img_localizations.dart';

class SyncBanner extends StatelessWidget {
  const SyncBanner({
    super.key,
    required this.syncInProgress,
  });

  final Stream<bool> syncInProgress;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: syncInProgress,
      initialData: false,
      builder: (context, snapshot) {
        final isSyncing = snapshot.data ?? false;
        return AnimatedSize(
          duration: Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: isSyncing
              ? Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          ImgLocalizations.of(context).syncInProgress,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                )
              : SizedBox.shrink(),
        );
      },
    );
  }
}

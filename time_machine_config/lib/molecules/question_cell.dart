import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:expandable/expandable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

class QuestionCell extends StatelessWidget {
  const QuestionCell({
    super.key,
    required this.title,
    required this.body,
    this.controller,
  });

  final String title;
  final String body;
  final ExpandableController? controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(12),
      child: ExpandableNotifier(
        child: ScrollOnExpand(
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: ExpandablePanel(
              header: Padding(
                padding: EdgeInsets.all(12),
                child: Text(title,
                  style: TextTheme.of(context).titleLarge,
                ),
              ),
              collapsed: SizedBox.shrink(),
              expanded: MarkdownBody(
                data: body,
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  code: TextStyle(
                    fontFamily: 'MaterialIcons',
                    fontSize: 14,
                  ),
                ),
                onTapLink: (_, href, _) {
                  if (href != null) {
                    unawaited(launchUrlString(href));
                  }
                },
              ),
              controller: controller,
              builder: (context, collapsed, expanded) {
                return Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Expandable(
                    collapsed: collapsed,
                    expanded: expanded,
                    theme: const ExpandableThemeData(crossFadePoint: 0),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

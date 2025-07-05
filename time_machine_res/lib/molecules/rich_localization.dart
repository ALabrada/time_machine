import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

class RichLocalization extends StatelessWidget {
  const RichLocalization({
    super.key,
    required this.text,
    this.iconSize=14,
    this.onTapLink,
    this.textAlign,
  });

  final String text;
  final double iconSize;
  final MarkdownTapLinkCallback? onTapLink;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: text,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        code: TextStyle(
          fontFamily: 'MaterialIcons',
          fontSize: iconSize,
        ),
        textAlign: _alignment(),
      ),
      onTapLink: onTapLink,
    );
  }

  WrapAlignment? _alignment() {
    final value = textAlign;
    if (value == null) {
      return null;
    }
    switch (value) {
      case TextAlign.left:
        return WrapAlignment.start;
      case TextAlign.right:
        return WrapAlignment.end;
      case TextAlign.center:
        return WrapAlignment.center;
      default:
        return WrapAlignment.spaceEvenly;
    }
  }
}

extension IconMarkdown on IconData {
  String get md {
    final name = String.fromCharCode(codePoint);
    return "`$name`";
  }
}

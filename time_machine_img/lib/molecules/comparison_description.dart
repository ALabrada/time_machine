import 'package:flutter/material.dart';
import 'package:image_compare_slider/image_compare_slider.dart';
import 'package:time_machine_res/tokens/colors.dart';
import 'package:time_machine_db/time_machine_db.dart';

import '../l10n/img_localizations.dart';

class ComparisonDescription extends StatelessWidget {
  const ComparisonDescription({
    super.key,
    this.firstPicture,
    this.secondPicture,
    this.match,
    this.direction=SliderDirection.bottomToTop,
  });

  final Picture? firstPicture;
  final Picture? secondPicture;
  final double? match;
  final SliderDirection direction;

  @override
  Widget build(BuildContext context) {
    final labels = _labelsFor(context, direction);
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: background02.withAlpha(127),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              text: "${labels[0]}: ",
              style: TextTheme.of(context).bodyLarge?.merge(TextStyle(
                fontWeight: FontWeight.w600,
              )),
              children: [
                TextSpan(
                  text: firstPicture?.text ?? '',
                  style: TextTheme.of(context).bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              text: "${labels[1]}: ",
              style: TextTheme.of(context).bodyLarge?.merge(TextStyle(
                fontWeight: FontWeight.w600,
              )),
              children: [
                TextSpan(
                  text: secondPicture?.text ?? '',
                  style: TextTheme.of(context).bodyMedium,
                ),
              ],
            ),
          ),
          if (match != null)
            ...[
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  text: "${ImgLocalizations.of(context).comparisonMetric}: ",
                  style: TextTheme.of(context).bodyLarge?.merge(TextStyle(
                    fontWeight: FontWeight.w600,
                  )),
                  children: [
                    TextSpan(
                      text: "${(100.0 * match!).toStringAsFixed(0)}%",
                      style: TextTheme.of(context).bodyMedium,
                    ),
                  ],
                ),
              ),
            ]
        ],
      ),
    );
  }

  List<String> _labelsFor(BuildContext context, SliderDirection direction) {
    final loc = ImgLocalizations.of(context);
    switch (direction) {
      case SliderDirection.leftToRight:
        return [ loc.comparisonLeft, loc.comparisonRight];
      case SliderDirection.topToBottom:
        return [loc.comparisonTop, loc.comparisonBottom];
      case SliderDirection.rightToLeft:
        return [loc.comparisonRight, loc.comparisonLeft];
      default:
        return [loc.comparisonBottom, loc.comparisonTop];
    }
  }
}

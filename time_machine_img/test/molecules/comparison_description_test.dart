import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_machine_img/l10n/img_localizations.dart';
import 'package:time_machine_img/molecules/comparison_description.dart';

Future<void> pumpDescription(WidgetTester tester, double? match) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: ImgLocalizations.localizationsDelegates,
      supportedLocales: ImgLocalizations.supportedLocales,
      home: Scaffold(body: ComparisonDescription(match: match)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ComparisonDescription similarity', () {
    testWidgets('reports the score as a percentage', (tester) async {
      await pumpDescription(tester, 0.23);
      expect(find.textContaining('23%'), findsOneWidget);
    });

    testWidgets('rounds to whole percent', (tester) async {
      await pumpDescription(tester, 0.529);
      expect(find.textContaining('53%'), findsOneWidget);
    });

    // Guards against the verdict wording coming back: it is a judgement the
    // metric cannot support on every pair, and it was removed deliberately.
    testWidgets('shows no verdict wording', (tester) async {
      await pumpDescription(tester, 0.71);
      expect(find.textContaining('Likely the same place'), findsNothing);
      expect(find.textContaining('Probably a different place'), findsNothing);
      expect(find.textContaining('71%'), findsOneWidget);
    });

    testWidgets('shows nothing when the pair could not be compared',
        (tester) async {
      await pumpDescription(tester, null);
      expect(find.textContaining('Similarity'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    });
  });
}

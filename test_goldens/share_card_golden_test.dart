// The share card at its export size (item 3.11, ADR 0023): one golden per
// format and theme, and the card with a commentary's opening. They are the
// images a student sends; design/redesign/share/ holds the prototype's own
// exports of the same cards.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/share_card.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/share/share_sheet.dart';

import '../test/handoff/fixtures.dart';
import 'golden_fonts.dart';

void main() {
  final data = HandoffContent();
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadGoldenFonts();
    await data.open();
  });
  tearDownAll(data.close);

  final cards = <String, (CardFormat, int, int, ShareCardPalette, bool)>{
    'paper-portrait-1': (CardFormat.portrait, 226, 226, ShareCardPalette.paper, false),
    'paper-square-4': (CardFormat.square, 226, 229, ShareCardPalette.paper, false),
    'paper-story-10': (CardFormat.story, 235, 244, ShareCardPalette.paper, false),
    'paper-story-excerpt': (CardFormat.story, 226, 226, ShareCardPalette.paper, true),
    'night-portrait-1-jade': (CardFormat.portrait, 226, 226, ShareCardPalette.night(TzNightPage.jade), false),
    'night-square-4-jade': (CardFormat.square, 226, 229, ShareCardPalette.night(TzNightPage.jade), false),
    'night-story-10-wisteria': (CardFormat.story, 235, 244, ShareCardPalette.night(TzNightPage.wisteria), false),
    // Verse 230's two reader symbols in their frames, in the card's own rubric (ADR 0024).
    'paper-portrait-1-symbols': (CardFormat.portrait, 230, 230, ShareCardPalette.paper, false),
    'night-square-4-symbols-lapis': (CardFormat.square, 229, 232, ShareCardPalette.night(TzNightPage.lapis), false),
  };

  for (final MapEntry(key: name, value: (format, from, to, palette, quoted)) in cards.entries) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = format.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final excerpt = quoted
          ? await tester.runAsync(() => loadExcerpt(data.content, data.content.books.defaultBook, from))
          : null;
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ShareCard(data: shareCardData(data.content, from, to, format, excerpt: excerpt), palette: palette),
      ));
      await expectLater(find.byType(ShareCard), matchesGoldenFile('goldens/share/$name.png'));
    });
  }
}

// Item 3.11 (ADRs 0010, 0023): the share card. Three export sizes; the verses
// fitted between the format's largest size and a 32 px floor, stacked or as
// pairs, whichever is larger, with no hemistich wrapping; a PNG of exactly the
// format's pixels.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/share_card.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/share/share_sheet.dart';

import '../test_goldens/golden_fonts.dart';
import 'handoff/fixtures.dart';

void main() {
  final data = HandoffContent();
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadGoldenFonts();
    await data.open();
  });
  tearDownAll(data.close);

  ShareCardData card(int from, int to, CardFormat format, {CardExcerpt? excerpt}) =>
      shareCardData(data.content, from, to, format, excerpt: excerpt);

  test('three sizes: 1080 wide; the most verses each holds at the floor; where the fitter starts', () {
    expect([for (final f in CardFormat.values) (f.name, f.size, f.maxVerses, f.maxSize)], [
      ('square', const Size(1080, 1080), 4, 60.0),
      ('portrait', const Size(1080, 1350), 6, 64.0),
      ('story', const Size(1080, 1920), 10, 68.0),
    ]);
    expect(CardFormat.minSize, 32);
    expect([for (final f in CardFormat.values) (f.ar, f.ratio)], [('مربع', '١:١'), ('طولي', '٤:٥'), ('قصة', '٩:١٦')]);
  });

  test('the fit, as the reference cards: one verse stacked at 64; four in a square stacked at 44; ten in a story as pairs at 34', () {
    final one = fitShareCard(card(226, 226, CardFormat.portrait));
    expect((one.size, one.pair, one.overflow), (64.0, false, false));
    final four = fitShareCard(card(226, 229, CardFormat.square));
    expect((four.size, four.pair, four.overflow), (44.0, false, false));
    final ten = fitShareCard(card(235, 244, CardFormat.story));
    expect((ten.size, ten.pair, ten.overflow), (34.0, true, false));
    const excerpt = CardExcerpt(
        text: 'أمر الناظم بتحريك كل حرف ساكن وقع آخر الكلمة التي هو فيها وكان صحيحا، بتحريك هذا الحرف بشكل الهمز الذي بعده أي بحركته، '
            'سواء كانت تلك الحركة فتحة أو ضمة أو كسرة، مع حذف الهمز بعد نقل حركته إلى الساكن قبله وذلك لورش…',
        source: 'الوافي في شرح الشاطبية · عبد الفتاح القاضي');
    final quoted = fitShareCard(card(226, 226, CardFormat.story, excerpt: excerpt));
    expect((quoted.size, quoted.pair, quoted.overflow), (64.0, false, false));
  });

  test('every chapter\'s opening verses fit each format at its limit; one more does not', () {
    final matn = data.content.matn;
    for (final format in CardFormat.values) {
      for (final ch in matn.chapters.where((c) => c.verseCount > format.maxVerses)) {
        final fit = fitShareCard(card(ch.fromVerse, ch.fromVerse + format.maxVerses - 1, format));
        expect(fit.overflow, isFalse, reason: '${format.name}: ${format.maxVerses} verses from ${ch.fromVerse}');
        expect(fit.size, greaterThanOrEqualTo(CardFormat.minSize));
      }
    }
  });

  test('what may be shared: 1–10 verses of one chapter', () {
    expect(shareLimitReason(data.content, 226, 226), isNull);
    expect(shareLimitReason(data.content, 226, 234), isNull);
    expect(shareLimitReason(data.content, 235, 244), isNull);
    expect(shareLimitReason(data.content, 235, 245), 'المشاركة حتى ١٠ أبيات من باب واحد'); // eleven
    expect(shareLimitReason(data.content, 233, 236), 'المشاركة حتى ١٠ أبيات من باب واحد'); // two chapters
  });

  testWidgets('the card: head, verses, footer; several verses carry the chapter\'s number and a range', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> show(ShareCardData d) => tester.pumpWidget(MaterialApp(home: Center(child: ShareCard(data: d))));

    await show(card(226, 226, CardFormat.portrait));
    expect(tester.getSize(find.byType(ShareCard)), const Size(1080, 1350));
    expect(find.text('الباب الحادي عشر · البيت ٢٢٦'), findsOneWidget);
    expect(find.text(data.content.matn.chapterOfVerse(226).title), findsOneWidget);
    expect(find.text('تيسير الشاطبية'), findsOneWidget);
    expect(find.text('حرز الأماني ووجه التهاني · الإمام الشاطبي'), findsOneWidget);
    expect(find.byType(ShareCardVerse), findsOneWidget);
    expect(tester.getSemantics(find.byType(ShareCard)).label, contains('البيت ٢٢٦'));

    await show(card(226, 229, CardFormat.square));
    expect(tester.getSize(find.byType(ShareCard)), const Size(1080, 1080));
    expect(find.textContaining('الباب الحادي عشر · الأبيات'), findsOneWidget);
    expect(find.byType(ShareCardVerse), findsNWidgets(4));
    // The verses stay inside the body: between the head and the footer's rule.
    final body = tester.getRect(find.byKey(ShareCard.bodyKey));
    for (final e in find.byType(ShareCardVerse).evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      expect(r.top >= body.top - 0.5 && r.bottom <= body.bottom + 0.5, isTrue, reason: '$r in $body');
    }
  });

  testWidgets('the exported PNG is exactly the format\'s pixels, whatever size the preview is drawn at', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    for (final format in CardFormat.values) {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            child: FittedBox(child: RepaintBoundary(key: key, child: ShareCard(data: card(226, 226, format)))),
          ),
        ),
      ));
      final ui.Image image = (await tester.runAsync(() => captureCard(key)))!;
      expect((image.width, image.height), (format.size.width.toInt(), format.size.height.toInt()), reason: format.name);
    }
  });

  test('palettes: paper and night, the night rubric being the chosen ink', () {
    expect(ShareCardPalette.paper.rubric, const Color(0xFF8E2A5A));
    expect(ShareCardPalette.night(TzNightPage.wisteria).rubric, TzNightPage.wisteria.accent);
    expect(ShareCardPalette.night(TzNightPage.jade).rubric, TzNightPage.jade.accent);
    expect(ShareCardPalette.night(TzNightPage.jade).background, isNot(ShareCardPalette.paper.background));
  });
}

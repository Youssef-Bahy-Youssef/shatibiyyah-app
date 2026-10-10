// Item 3.11 (ADRs 0010, 0023): the share sheet. One card image of 1–10 verses
// from one chapter: the three sizes with their limits, the optional quoted
// opening of a commentary for up to three verses, «مشاركة الصورة» (the image
// alone) and «حفظ».
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shatibiyyah/ui/design/components/share_card.dart';
import 'package:shatibiyyah/ui/design/components/share_controls.dart';
import 'package:shatibiyyah/ui/design/components/tz_switch.dart';
import 'package:shatibiyyah/ui/design/components/verse_unit.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/share/share_sheet.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';
import 'package:shatibiyyah/utils/arabic.dart';

import 'handoff/fixtures.dart';
import 'handoff/handoff.dart';

void main() {
  final data = HandoffContent();
  setUpAll(data.open);
  tearDownAll(data.close);

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Lets the database read behind the excerpt finish.
  Future<void> load(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// Waits for real work (the card's capture and encoding) until [done].
  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  final shared = <ShareParams>[];
  final saved = <(String, Uint8List)>[];
  final notices = <String>[];

  Future<void> open(WidgetTester tester, int from, int to, {bool saves = true}) async {
    shared.clear();
    saved.clear();
    notices.clear();
    await pumpPhone(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showShareSheet(context, data.content, from,
                  to: to,
                  share: (p) async => shared.add(p),
                  save: (name, png) async {
                    if (!saves) throw StateError('no room');
                    saved.add((name, png));
                    return true;
                  },
                  onNotice: notices.add),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  ShareFormatButton format(WidgetTester tester, String ar) =>
      tester.widget<ShareFormatButton>(find.widgetWithText(ShareFormatButton, ar));
  ShareCard card(WidgetTester tester) => tester.widget<ShareCard>(find.byType(ShareCard));

  Future<(int, int)> pngSize(WidgetTester tester, Uint8List png) async {
    final image = (await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(png);
      return (await codec.getNextFrame()).image;
    }))!;
    return (image.width, image.height);
  }

  testWidgets('one verse: the portrait card by default; «مشاركة الصورة» sends the image alone, 1080 × 1350', (tester) async {
    await open(tester, 226, 226);
    expect(find.text('مشاركة البيت ٢٢٦'), findsOneWidget);
    expect(find.text('صورة بحجم ١٠٨٠×١٣٥٠'), findsOneWidget);
    expect((card(tester).data.format, card(tester).data.verses.length), (CardFormat.portrait, 1));
    expect([for (final f in ['مربع', 'طولي', 'قصة']) (format(tester, f).selected, format(tester, f).enabled)],
        [(false, true), (true, true), (false, true)]);
    expect(find.byKey(ShareSheet.whyKey), findsNothing);

    await tester.tap(find.text('مشاركة الصورة'));
    await until(tester, () => shared.isNotEmpty);
    expect(shared, hasLength(1));
    expect(shared.single.text, isNull); // no text beside the image
    final file = shared.single.files!.single;
    expect(shared.single.fileNameOverrides, ['taysir-226.png']);
    expect(file.mimeType, 'image/png');
    expect(await pngSize(tester, (await tester.runAsync(file.readAsBytes))!), (1080, 1350));
    expect(find.byType(ShareSheet), findsNothing);
    await unmount(tester);
  });

  testWidgets('choosing a size changes the card and its stated pixels; «حفظ» saves that image and says so', (tester) async {
    await open(tester, 226, 229);
    expect(find.text('مشاركة الأبيات ${isolatedRange(226, 229)}'), findsOneWidget);
    await tester.tap(find.widgetWithText(ShareFormatButton, 'مربع'));
    await tester.pump();
    expect(card(tester).data.format, CardFormat.square);
    expect(find.text('صورة بحجم ١٠٨٠×١٠٨٠'), findsOneWidget);
    expect(tester.getSize(find.byKey(ShareSheet.frameKey)), const Size(300, 300));

    await tester.tap(find.text('حفظ'));
    await until(tester, () => notices.isNotEmpty);
    expect(saved.single.$1, 'taysir-226-229.png');
    expect(await pngSize(tester, saved.single.$2), (1080, 1080));
    expect(notices, ['حُفظت الصورة']);
    expect(find.byType(ShareSheet), findsNothing);
    await unmount(tester);
  });

  testWidgets('a failed save keeps the sheet and says «تعذّر الحفظ»', (tester) async {
    await open(tester, 226, 226, saves: false);
    await tester.tap(find.text('حفظ'));
    await until(tester, () => find.text('تعذّر الحفظ').evaluate().isNotEmpty);
    expect(find.byType(ShareSheet), findsOneWidget);
    expect(find.text('تعذّر الحفظ'), findsOneWidget);
    expect(notices, isEmpty);
    await unmount(tester);
  });

  testWidgets('ten verses: the story card as pairs; the square and the portrait are disabled, with the limits stated', (tester) async {
    await open(tester, 235, 244);
    expect((card(tester).data.format, card(tester).data.verses.length), (CardFormat.story, 10));
    expect([for (final f in ['مربع', 'طولي', 'قصة']) (format(tester, f).selected, format(tester, f).enabled)],
        [(false, false), (false, false), (true, true)]);
    expect(find.text('المربع يتسع حتى ٤ أبيات؛ الطولي حتى ٦، والقصة حتى ١٠.'), findsOneWidget);
    await tester.tap(find.widgetWithText(ShareFormatButton, 'مربع'), warnIfMissed: false);
    await tester.pump();
    expect(card(tester).data.format, CardFormat.story); // a disabled size is not chosen
    // More than three verses: no excerpt, and the row says so.
    expect(find.text('متاح حتى ٣ أبيات'), findsOneWidget);
    expect(tester.widget<TzSwitch>(find.byType(TzSwitch)).onChanged, isNull);
    await unmount(tester);
  });

  testWidgets('five verses open on the portrait; seven on the story', (tester) async {
    await open(tester, 235, 239);
    expect(card(tester).data.format, CardFormat.portrait);
    expect(format(tester, 'مربع').enabled, isFalse);
    await unmount(tester);
    await open(tester, 235, 241);
    expect(card(tester).data.format, CardFormat.story);
    await unmount(tester);
  });

  testWidgets('the excerpt: the opening of a book\'s explanation, quoted and attributed; the chips choose the book', (tester) async {
    await open(tester, 226, 226);
    expect(card(tester).data.excerpt, isNull);
    expect(find.byType(ShareBookChip), findsNothing);
    await tester.tap(find.text('بدون'));
    await load(tester);
    expect(find.text('مضاف'), findsOneWidget);
    final books = data.content.books.books;
    expect(find.byType(ShareBookChip), findsNWidgets(books.length));
    final first = card(tester).data.excerpt!;
    final own = data.content.books.defaultBook;
    expect(first.source, '${own.title} · ${own.author}');
    expect(first.text, isNotEmpty);
    // It is the book's own words: the opening of its first segment on the verse.
    final block = (await tester.runAsync(() => data.content.books.blocksForVerse(own.id, 226)))!.first;
    final segment = (await tester.runAsync(() => data.content.books.segments(block.id)))!.first;
    expect(segment.text.replaceAll(RegExp(r'\s+'), ' '), contains(first.text.substring(0, 40)));

    final other = books.firstWhere((b) => b.id != own.id);
    await tester.tap(find.widgetWithText(ShareBookChip, other.shortTitle));
    await load(tester);
    expect(card(tester).data.excerpt!.source, startsWith(other.title));
    expect(card(tester).data.excerpt!.text, isNot(first.text));

    await tester.tap(find.text('مضاف'));
    await tester.pump();
    expect(card(tester).data.excerpt, isNull);
    expect(find.byType(ShareBookChip), findsNothing);
    await unmount(tester);
  });

  testWidgets('from the reader: the verse menu shares its verse; a selection shares its run, or says why it cannot', (tester) async {
    final ReaderController r = await data.reader(tester, audio: true);
    r.setTextMode(true);
    await pumpPhone(tester, AppShell(reader: r));
    Finder unit(int v) => find.byWidgetPredicate((w) => w is VerseUnit && w.number == ar(v));

    await tester.longPress(unit(227));
    await settle(tester);
    await tester.tap(find.text('مشاركة'));
    await settle(tester);
    expect(find.text('مشاركة البيت ٢٢٧'), findsOneWidget);
    Navigator.of(tester.element(find.byType(ShareSheet))).pop();
    await settle(tester);

    r.startSelection(226);
    await tester.runAsync(() => r.tapVerse(228));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('مشاركة'));
    await settle(tester);
    expect(find.text('مشاركة الأبيات ${isolatedRange(226, 228)}'), findsOneWidget);
    expect(r.selecting, isFalse);
    Navigator.of(tester.element(find.byType(ShareSheet))).pop();
    await settle(tester);

    // Two chapters: the button stays, dimmed, and a tap gives the reason.
    r.startSelection(233);
    await tester.runAsync(() => r.tapVerse(236));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('مشاركة، المشاركة حتى ١٠ أبيات من باب واحد'));
    await settle(tester);
    expect(find.byType(ShareSheet), findsNothing);
    expect(r.notice, 'المشاركة حتى ١٠ أبيات من باب واحد');
    expect(r.selecting, isTrue);
    await unmount(tester);
  });
}

// test/handoff/states.dart — every state of the handoff as the app reaches it:
// the tab, whether a recording is on the device, and what to do before looking.
// The goldens draw each one (test_goldens/handoff_golden_test.dart); the
// accessibility audit checks each one (test/handoff/states_accessibility_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/data/user_store.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/services/download_manager.dart';
import 'package:shatibiyyah/ui/design/components/commentary_inline.dart';
import 'package:shatibiyyah/ui/design/components/dock.dart';
import 'package:shatibiyyah/ui/design/components/share_controls.dart';
import 'package:shatibiyyah/ui/design/components/stat_tile.dart';
import 'package:shatibiyyah/ui/design/components/verse_unit.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/reader/verse_rubrics.dart';
import 'package:shatibiyyah/ui/share/share_sheet.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';
import 'package:shatibiyyah/ui/shell/saved_screen.dart';
import 'package:shatibiyyah/utils/arabic.dart';
import 'fixtures.dart';

/// A state of the handoff: the tab it is on, whether a recording is on the device,
/// and what to do before the shot.
typedef HandoffState = ({
  DockTab tab,
  bool audio,
  DownloadPhase? download,
  Future<void> Function(WidgetTester, ReaderController, HandoffContent) setup
});

/// The player open on the section 226–234, set as the design's sample: 1.25×,
/// each verse three times, a 2 s gap. Then [tile]'s picker, if any.
Future<void> _player(WidgetTester tester, ReaderController r, [String? tile]) async {
  r
    ..setSpeed(1.25)
    ..setVerseRepeats(3)
    ..setGap(2000);
  await tester.runAsync(() => r.playScope(const PlaybackScope(226, 234)));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.bySemanticsLabel(RegExp('^فتح المشغّل')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  if (tile == null) return;
  await tester.tap(find.widgetWithText(StatTile, tile));
}

Future<void> _nothing(WidgetTester _, ReaderController _, HandoffContent _) async {}

/// «المحفوظ» as the design draws it: a bookmark on verse 1001 just swiped away
/// (its undo notice showing), and the first row held 100 px aside over «حذف».
Future<void> _savedSwiped(WidgetTester tester, ReaderController r, HandoffContent _) async {
  await tester.runAsync(() => r.personal!.saveBookmark(1001, color: BookmarkColor.values[1], tag: BookmarkTag.muraja));
  await tester.pump();
  await tester.drag(find.text('البيت ١٠٠١'), const Offset(-390, 0));
  // The delete is a real database write: wait for its result (the row gone, the
  // undo notice up), not for a fixed time. The clock still ends 1.2 s on, so the
  // notice is drawn at the same moment of its life every time.
  var waited = 0;
  bool done() => find.text('البيت ١٠٠١').evaluate().isEmpty && find.textContaining('أُزيل').evaluate().isNotEmpty;
  while (!done() && waited < 1000) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
    waited += 20;
  }
  await tester.pump(Duration(milliseconds: 1200 - waited));
  final gesture = await tester.startGesture(tester.getCenter(find.byType(SavedRow).first));
  addTearDown(gesture.removePointer);
  await gesture.moveBy(const Offset(-30, 0)); // taken as the start of a drag
  await gesture.moveBy(const Offset(-100, 0));
}

/// The share sheet over the reader, for [from]…[to], in a chosen size, with or
/// without the quoted opening of the default book.
Future<void> _share(WidgetTester tester, HandoffContent d, int from, int to, {String? format, bool excerpt = false}) async {
  showShareSheet(tester.element(find.byType(AppShell)), d.content, from, to: to);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  if (format != null) {
    await tester.tap(find.widgetWithText(ShareFormatButton, format));
    await tester.pump();
  }
  if (!excerpt) return;
  await tester.tap(find.text('بدون'));
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// «الشرح» open on [verse] as a sheet: at rest, or at [full] height with the
/// quotation [chip] of the verse lit in the matn strip.
Future<void> _commentary(WidgetTester tester, ReaderController r, HandoffContent d,
    {int verse = 226, bool text = true, String? book, bool full = false, String? chip}) async {
  Future<void> loaded() async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  r.setTextMode(text);
  if (book != null) r.setCommentaryBook(d.content.books.books.firstWhere((b) => b.shortTitle == book).id);
  await tester.pump(const Duration(milliseconds: 400));
  r.openCommentary(verse);
  await loaded();
  if (full) {
    await tester.tap(find.byTooltip('ملء الشاشة'));
    await loaded();
  }
  if (chip == null) return;
  final quote = find.byWidgetPredicate((w) => w is QuoteChip && w.words == chip);
  await tester.ensureVisible(quote);
  await tester.pump();
  await tester.tap(quote);
  await loaded();
}

/// Moves text mode's column so verse [verse] starts [top] dp down the screen, where the design's render has it.
Future<void> _standAt(WidgetTester tester, int verse, double top) async {
  final unit = find.byWidgetPredicate((w) => w is VerseUnit && w.number == ar(verse));
  final list = tester.state<ScrollableState>(find.ancestor(of: unit, matching: find.byType(Scrollable)).first).position;
  list.jumpTo(list.pixels + tester.getTopLeft(unit).dy - top);
  await tester.pump(const Duration(milliseconds: 400));
}

final Map<String, HandoffState> handoffStates = {
  'reader-playing': (
    tab: DockTab.matn,
    audio: true,
    download: null,
    setup: (tester, r, _) => tester.runAsync(() => r.playScope(const PlaybackScope(226, 234)))
  ),
  'reader-none': (tab: DockTab.matn, audio: false, download: null, setup: _nothing),
  'reader-downloading': (tab: DockTab.matn, audio: false, download: DownloadPhase.downloading, setup: _nothing),
  'reader-failed': (tab: DockTab.matn, audio: false, download: DownloadPhase.failed, setup: _nothing),
  'verse': (tab: DockTab.matn, audio: true, download: null, setup: (_, r, _) async => r.openMenu(229)),
  'heading': (
    tab: DockTab.matn,
    audio: true,
    download: null,
    setup: (_, r, d) async => r.openHeading(d.content.matn.chapters.indexWhere((c) => c.fromVerse == 226))
  ),
  'player-main': (tab: DockTab.matn, audio: true, download: null, setup: (tester, r, _) => _player(tester, r)),
  'player-repeat': (tab: DockTab.matn, audio: true, download: null, setup: (tester, r, _) => _player(tester, r, 'تكرار البيت')),
  'player-speed': (tab: DockTab.matn, audio: true, download: null, setup: (tester, r, _) => _player(tester, r, 'السرعة')),
  'textmode-reading': (tab: DockTab.matn, audio: true, download: null, setup: (_, r, _) async => r.setTextMode(true)),
  'textmode-playing': (
    tab: DockTab.matn,
    audio: true,
    download: null,
    setup: (tester, r, _) async {
      r.setTextMode(true);
      await tester.runAsync(() => r.playScope(const PlaybackScope(226, 234)));
      await tester.runAsync(() => r.tapVerse(227));
      await tester.pump(const Duration(milliseconds: 400));
      await _standAt(tester, 227, 259.5); // the design's sample: the recited verse 160 dp down the list
    }
  ),
  'textmode-display': (
    tab: DockTab.matn,
    audio: true,
    download: null,
    setup: (tester, r, _) async {
      r.setTextMode(true);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('العرض'));
    }
  ),
  'index': (
    tab: DockTab.contents,
    audio: true,
    download: null,
    setup: (tester, r, _) => tester.runAsync(() => r.playScope(const PlaybackScope(226, 234)))
  ),
  'textmode-symbol': (
    tab: DockTab.matn,
    audio: true,
    download: null,
    setup: (tester, r, _) async {
      // The design's sample: verse 227 loaded, the list moved so 230 stands 140 dp down it.
      r.setTextMode(true);
      await tester.runAsync(() => r.tapVerse(227));
      await tester.pump(const Duration(milliseconds: 400));
      await _standAt(tester, 230, 239.5);
      r.openSymbol(230, verseRubrics(r.content, 230).first);
    }
  ),
  'saved-bookmarks': (tab: DockTab.saved, audio: false, download: null, setup: _savedSwiped),
  'saved-notes': (tab: DockTab.saved, audio: false, download: null, setup: (tester, _, _) => tester.tap(find.text('الملاحظات ٠'))),
  'share-one': (tab: DockTab.matn, audio: true, download: null, setup: (tester, _, d) => _share(tester, d, 226, 226)),
  'share-four': (
    tab: DockTab.matn,
    audio: true,
    download: null,
    setup: (tester, _, d) => _share(tester, d, 226, 229, format: 'مربع')
  ),
  'share-excerpt': (
    tab: DockTab.matn,
    audio: true,
    download: null,
    setup: (tester, _, d) => _share(tester, d, 226, 226, format: 'قصة', excerpt: true)
  ),
  'share-ten': (tab: DockTab.matn, audio: true, download: null, setup: (tester, _, d) => _share(tester, d, 235, 244)),
  'commentary-half': (tab: DockTab.matn, audio: true, download: null, setup: (tester, r, d) => _commentary(tester, r, d)),
  'commentary-page': (
    tab: DockTab.matn,
    audio: true,
    download: null,
    setup: (tester, r, d) => _commentary(tester, r, d, text: false)
  ),
  'commentary-full': (
    tab: DockTab.matn,
    audio: true,
    download: null,
    setup: (tester, r, d) => _commentary(tester, r, d, full: true, chip: 'مسهلا')
  ),
  'commentary-grouped': (
    tab: DockTab.matn,
    audio: true,
    download: null,
    setup: (tester, r, d) => _commentary(tester, r, d, verse: 231, full: true, chip: 'والبدء بالأصل فضّلا')
  ),
  'commentary-siraj': (
    tab: DockTab.matn,
    audio: true,
    download: null,
    setup: (tester, r, d) => _commentary(tester, r, d, book: 'سراج القارئ', full: true)
  ),
  'settings-main': (tab: DockTab.settings, audio: false, download: null, setup: _nothing),
  'settings-picker': (
    tab: DockTab.settings,
    audio: false,
    download: null,
    setup: (tester, _, _) => tester.tap(find.text(TzNightPage.pickerTitle))
  ),
};

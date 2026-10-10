// The section (ADR 0003): the run of verses the player is set to play. It starts
// where play was pressed. «تكرار المقطع» returns to its first verse, never to a
// chapter's first verse the listener did not choose.
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';

import 'handoff/fixtures.dart';

void main() {
  final data = HandoffContent();
  setUpAll(data.open);
  tearDownAll(data.close);

  (int, int, bool) section(ReaderController r) {
    final s = r.engine!.plan.scope;
    return (s.fromVerse, s.toVerse, s.fromChapterTitle);
  }

  /// The reader on verse 226 (chapter 226–234) with a recording loaded, nothing playing.
  Future<ReaderController> reader(WidgetTester tester) => data.reader(tester, audio: true, bookmarks: false);

  testWidgets('▶ with nothing chosen: from the current verse to the end of its chapter', (tester) async {
    final r = await reader(tester);
    await tester.runAsync(() => r.tapVerse(230));
    await tester.runAsync(r.playPause);
    expect((r.playing, r.verse), (true, 230));
    expect(section(r), (230, 234, false));
    // The section's first verse is where a section repeat returns: 230, not 226.
    final plan = PlaybackPlan(r.engine!.windows, r.engine!.plan.scope, const PlaybackSettings(sectionRepeats: 2));
    final verses = <int>[];
    PlanAction a = plan.start();
    while (a is! Finished) {
      if (a is PlayRange) verses.add(a.verse);
      a = plan.advance();
    }
    expect(verses, [230, 231, 232, 233, 234, 230, 231, 232, 233, 234]);
    await tester.runAsync(r.playPause);
  });

  testWidgets('«الاستماع إلى؟», a selection and «تشغيل الباب» each set their own section', (tester) async {
    final r = await reader(tester);
    final last = data.content.matn.lastVerse;
    await tester.runAsync(() => r.playScope(const PlaybackScope(229, 229))); // «البيت فقط»
    expect(section(r), (229, 229, false));
    await tester.runAsync(() => r.playScope(PlaybackScope(229, last))); // «إلى نهاية المتن»: not clamped to a chapter
    expect(section(r), (229, last, false));

    r.startSelection(228);
    await tester.runAsync(() => r.tapVerse(231));
    await tester.runAsync(r.playSelection);
    expect(section(r), (228, 231, false)); // exactly the selected verses

    await tester.runAsync(() => r.playChapter(data.content.matn.chapterOfVerse(226)));
    expect(section(r), (226, 234, true)); // the whole chapter, from its spoken title
    await tester.runAsync(r.playPause);
  });

  testWidgets('a tapped verse while playing: inside the section it stays; outside starts one from there', (tester) async {
    final r = await reader(tester);
    await tester.runAsync(() => r.tapVerse(230));
    await tester.runAsync(r.playPause);
    await tester.runAsync(() => r.tapVerse(232));
    expect((r.verse, section(r)), (232, (230, 234, false)));
    await tester.runAsync(() => r.tapVerse(240)); // another chapter (235–254)
    expect((r.verse, section(r)), (240, (240, 254, false)));
    await tester.runAsync(() => r.tapVerse(228)); // before any section: from there to the end of its chapter
    expect((r.verse, section(r)), (228, (228, 234, false)));
    await tester.runAsync(r.playPause);
  });

  testWidgets('paused: ▶ on a verse inside the section keeps it; on one outside it starts a new one', (tester) async {
    final r = await reader(tester);
    await tester.runAsync(() => r.playScope(const PlaybackScope(228, 232)));
    await tester.runAsync(r.playPause); // pause
    expect(r.playing, isFalse);
    await tester.runAsync(() => r.tapVerse(231));
    await tester.runAsync(r.playPause);
    expect((r.playing, r.verse, section(r)), (true, 231, (228, 232, false)));

    await tester.runAsync(r.playPause);
    await tester.runAsync(() => r.tapVerse(233)); // past the section's end
    await tester.runAsync(r.playPause);
    expect((r.verse, section(r)), (233, (233, 234, false)));
    await tester.runAsync(r.playPause);
  });

  testWidgets('▶ in the middle of a verse resumes it: same section, same counters', (tester) async {
    final r = await reader(tester);
    r.setVerseRepeats(3);
    await tester.runAsync(() => r.playScope(const PlaybackScope(228, 232)));
    r.engine!.plan.advance(); // the second play of verse 228
    await tester.runAsync(r.playPause);
    await tester.runAsync(r.playPause);
    expect((r.playing, section(r), r.engine!.plan.verseRepetition), (true, (228, 232, false), 2));
    // A new speed keeps them; a jump starts them again (ADR 0004).
    r.setSpeed(1.5);
    expect(r.engine!.plan.verseRepetition, 2);
    await tester.runAsync(() => r.tapVerse(229));
    expect(r.engine!.plan.verseRepetition, 1);
    await tester.runAsync(r.playPause);
  });
}

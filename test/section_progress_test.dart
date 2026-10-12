// The dock's bar and the player's scrubber over a section played from its start
// to its end: empty at the start, each verse as wide as it is long, full at the
// end, and the two always at the same place (SectionTime).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/domain/playback_windows.dart';
import 'package:shatibiyyah/ui/design/components/dock.dart';
import 'package:shatibiyyah/ui/design/components/section_scrubber.dart';
import 'package:shatibiyyah/ui/reader/player_sheet.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';

import 'handoff/fixtures.dart';
import 'handoff/handoff.dart';

void main() {
  final data = HandoffContent();
  setUpAll(data.open);
  tearDownAll(data.close);

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  /// The player's answer reaches the reader, and the screen is drawn.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tick(WidgetTester tester, TickingAudio audio, int ms) async {
    audio.tick(ms);
    await settle(tester);
  }

  /// The three verses 53–55 playing from their start, as «تشغيل» on a selection starts them.
  Future<(ReaderController, TickingAudio, PlaybackWindows)> playing(WidgetTester tester) async {
    final audio = TickingAudio();
    final r = await data.reader(tester, audio: true, bookmarks: false, port: audio);
    await pumpPhone(tester, AppShell(reader: r));
    await tester.runAsync(() => r.playScope(const PlaybackScope(53, 55)));
    await settle(tester);
    expect((r.playing, r.verse), (true, 53));
    return (r, audio, r.engine!.windows);
  }

  /// How much of the dock's bar is filled, 0…1.
  double bar(WidgetTester tester) =>
      tester.getSize(find.byKey(Dock.barFillKey)).width / (tester.getSize(find.byKey(Dock.rowKey)).width - 32);

  testWidgets('the bar is empty where the section starts and full where it ends', (tester) async {
    final (r, audio, w) = await playing(tester);
    final start = w.cue(53), total = w.verseEnd(55) - start;
    expect(bar(tester), 0);
    expect(find.textContaining('١ من ٣', findRichText: true), findsOneWidget);

    // Inside a verse it is where the recitation is, not at a fixed part of the verse.
    for (final part in [0.25, 0.75]) {
      final at = w.cue(53) + ((w.verseEnd(53) - w.cue(53)) * part).round();
      await tick(tester, audio, at);
      expect(bar(tester), closeTo((at - start) / total, 0.002));
    }

    // From one verse to the next it moves by that verse's share of the time.
    await tick(tester, audio, w.verseEnd(53) - 10);
    expect(r.verse, 54);
    expect(bar(tester), closeTo((w.cue(54) - start) / total, 0.002));
    await tick(tester, audio, w.verseEnd(54) - 10);
    expect(r.verse, 55);
    expect(find.textContaining('٣ من ٣', findRichText: true), findsOneWidget);
    expect(bar(tester), closeTo((w.cue(55) - start) / total, 0.002));
    final middle = (w.cue(55) + w.verseEnd(55)) ~/ 2;
    await tick(tester, audio, middle);
    expect(bar(tester), closeTo((middle - start) / total, 0.002));

    // The last verse ends: the section is over and the bar is full.
    await tick(tester, audio, w.verseEnd(55) - 10);
    expect((r.playing, r.verse, r.sectionEnded), (false, 55, true));
    expect(bar(tester), 1);

    // ▶ starts the section again: the bar is empty again.
    await tester.runAsync(r.playPause);
    await settle(tester);
    expect((r.playing, r.verse, r.sectionEnded), (true, 53, false));
    expect(bar(tester), 0);
    await tester.runAsync(r.playPause);
    await unmount(tester);
  });

  testWidgets('a verse repeated goes back to its start; a jump goes to the verse\'s start', (tester) async {
    final (r, audio, w) = await playing(tester);
    final start = w.cue(53), total = w.verseEnd(55) - start;
    r.setVerseRepeats(2);
    await tick(tester, audio, w.cue(54) - 2000);
    expect(bar(tester), closeTo((w.cue(54) - 2000 - start) / total, 0.002));
    await tick(tester, audio, w.verseEnd(53) - 10); // its first time ends: again from its start
    expect((r.verse, r.verseRepetition), (53, 2));
    expect(bar(tester), 0);
    await tick(tester, audio, w.verseEnd(53) - 10);
    expect(r.verse, 54);
    expect(bar(tester), closeTo((w.cue(54) - start) / total, 0.002));

    await tester.runAsync(r.next);
    await settle(tester);
    expect(r.verse, 55);
    expect(bar(tester), closeTo((w.cue(55) - start) / total, 0.002));
    await tester.runAsync(r.previous);
    await tester.runAsync(r.previous);
    await settle(tester);
    expect(r.verse, 53);
    expect(bar(tester), 0);
    await tester.runAsync(r.playPause);
    await unmount(tester);
  });

  testWidgets('the player\'s scrubber is at the same place as the dock\'s bar', (tester) async {
    final (r, audio, w) = await playing(tester);
    final start = w.cue(53), total = w.verseEnd(55) - start;
    double scrubber() =>
        tester.getSize(find.byKey(SectionScrubber.fillKey)).width / tester.getSize(find.byKey(SectionScrubber.trackKey)).width;

    final middle = (w.cue(54) + w.verseEnd(54)) ~/ 2;
    await tick(tester, audio, w.verseEnd(53) - 10);
    await tick(tester, audio, middle);
    final docked = bar(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('^فتح المشغّل')));
    await settle(tester);
    expect(find.byType(PlayerSheet), findsOneWidget);
    expect(scrubber(), closeTo(docked, 0.002));
    expect(scrubber(), closeTo((middle - start) / total, 0.002));
    // A tick where each later verse begins.
    final track = tester.getRect(find.byKey(SectionScrubber.trackKey));
    expect(
      [for (final e in find.byKey(SectionScrubber.tickKey).evaluate()) (track.right - tester.getRect(find.byWidget(e.widget)).center.dx) / track.width],
      [closeTo((w.cue(54) - start) / total, 0.002), closeTo((w.cue(55) - start) / total, 0.002)],
    );

    await tick(tester, audio, w.verseEnd(54) - 10);
    await tick(tester, audio, w.verseEnd(55) - 10);
    expect(r.sectionEnded, isTrue);
    expect(scrubber(), 1);
    final times = tester.widget<SectionScrubber>(find.byType(SectionScrubber));
    expect(times.start, times.end); // the time heard is the section's length
    await unmount(tester);
  });
}

// Item 3.13 (was 3.9; F-60, F-61): while a recitation plays, a position tick
// rebuilds nothing. The page image and the highlight are two layers: the glide
// of the highlight to the next verse (320 ms) repaints the highlight alone.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';

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

  /// The app on a phone with its animations running (pumpPhone turns them off).
  Future<void> pumpMoving(WidgetTester tester, ReaderController r) async {
    tester.view.physicalSize = kHandoffScreen;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = kHandoffPadding;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: tzThemeData(TzTheme.paper),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: AppShell(reader: r),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    // The scan decodes for real, so its arrival is not counted as a repaint later.
    final viewer = tester.element(find.byType(PageViewer));
    await tester.runAsync(() async {
      for (final n in [18, 19, 20]) {
        await precacheImage(AssetImage('assets/pages/page0$n.webp'), viewer);
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// The reader on the page, reciting verse 227 of the section 226–234.
  Future<(ReaderController, TickingAudio, int)> reciting(WidgetTester tester) async {
    final audio = TickingAudio();
    final r = await data.reader(tester, audio: true, bookmarks: false, port: audio);
    await pumpMoving(tester, r);
    await tester.runAsync(() => r.playScope(const PlaybackScope(226, 234)));
    await tester.runAsync(() => r.tapVerse(227));
    // The glide to 227 runs on frame time: several frames see it through.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final windows = await tester.runAsync(() => data.content.windowsFor(data.content.recordings.defaultRecording));
    expect((r.playing, r.verse), (true, 227));
    return (r, audio, windows!.cues[227]);
  }

  /// Sends [ms] to the engine and lets its state reach the reader.
  Future<void> tick(WidgetTester tester, TickingAudio audio, int ms) async {
    audio.tick(ms);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 16));
  }

  testWidgets('a page decoded ahead is drawn with the reader\'s first frame', (tester) async {
    final r = await data.reader(tester, bookmarks: false);
    Future<void> first(Widget home) async {
      tester.view.physicalSize = kHandoffScreen;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = kHandoffPadding;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: tzThemeData(TzTheme.paper),
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: home,
      ));
    }

    int drawn() => tester.state<PageViewerState>(find.byType(PageViewer)).overlayPage;

    // Left to the viewer, the scan is asked for in its first frame and comes later.
    imageCache.clear();
    imageCache.clearLiveImages();
    await first(AppShell(reader: r));
    expect(drawn(), 0);
    await unmount(tester);

    // What the launch does: verse 226's page is decoded before the reader is shown.
    imageCache.clear();
    imageCache.clearLiveImages();
    await first(const SizedBox());
    await tester.runAsync(() => PageViewer.warm(tester.element(find.byType(SizedBox)), 19));
    await first(AppShell(reader: r));
    expect(drawn(), 19);
    await unmount(tester);
  });

  testWidgets('ten position ticks: the reader tells no one, the page is neither rebuilt nor repainted', (tester) async {
    final (r, audio, start) = await reciting(tester);
    var told = 0;
    void count() => told++;
    r.addListener(count);
    final stages = PageViewer.debugStageBuilds, images = PageViewer.debugImageBuilds;
    // Each layer is behind its own repaint boundary.
    expect(tester.renderObject(find.byKey(PageViewer.imageKey)), isA<RenderRepaintBoundary>());
    expect(tester.renderObject(find.byKey(PageViewer.overlayKey)), isA<RenderRepaintBoundary>());
    final imagePaints = PageViewer.debugImagePaints, overlayPaints = PageViewer.debugOverlayPaints;

    for (var i = 1; i <= 10; i++) {
      await tick(tester, audio, start + 100 * i);
    }
    expect(told, 0);
    expect(PageViewer.debugStageBuilds - stages, lessThanOrEqualTo(1));
    expect(PageViewer.debugImageBuilds - images, 0);
    expect(PageViewer.debugImagePaints - imagePaints, 0);
    expect(PageViewer.debugOverlayPaints - overlayPaints, 0);
    expect(r.verse, 227);
    r.removeListener(count);
    await unmount(tester);
  });

  testWidgets('the next verse: the highlight glides for 320 ms on its own layer; the image is not touched', (tester) async {
    final (r, audio, _) = await reciting(tester);
    final windows = await tester.runAsync(() => data.content.windowsFor(data.content.recordings.defaultRecording));
    final images = PageViewer.debugImageBuilds;

    // The end of verse 227: the engine goes on to 228.
    audio.tick(windows!.cues[228] - 10);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(r.verse, 228);
    final imagePaints = PageViewer.debugImagePaints, overlayPaints = PageViewer.debugOverlayPaints;
    final stages = PageViewer.debugStageBuilds;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(PageViewer.debugOverlayPaints - overlayPaints, greaterThanOrEqualTo(5));
    expect(PageViewer.debugImagePaints - imagePaints, 0);
    expect(PageViewer.debugImageBuilds - images, 0);
    expect(PageViewer.debugStageBuilds - stages, 0); // a frame of the glide is a repaint, not a build
    // Once it is over, nothing repaints.
    await tester.pump(const Duration(milliseconds: 400));
    final settled = PageViewer.debugOverlayPaints;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(PageViewer.debugOverlayPaints - settled, 0);
    await unmount(tester);
  });

  testWidgets('a painter with the same fields does not repaint; the neighbouring pages are fetched ahead', (tester) async {
    final r = await data.reader(tester, audio: true, bookmarks: false);
    await pumpPhone(tester, AppShell(reader: r));
    final paint = tester.widget<CustomPaint>(find.descendant(of: find.byKey(PageViewer.overlayKey), matching: find.byType(CustomPaint)));
    // The same state built again: the same fields.
    r.showNotice('…');
    await tester.pump();
    final again = tester.widget<CustomPaint>(find.descendant(of: find.byKey(PageViewer.overlayKey), matching: find.byType(CustomPaint)));
    expect(again.painter!.shouldRepaint(paint.painter!), isFalse);
    // The night page is another picture: both layers are new.
    final before = PageViewer.debugImageBuilds;
    await pumpPhone(tester, AppShell(reader: r), tz: TzTheme.dark);
    final night = tester.widget<CustomPaint>(find.descendant(of: find.byKey(PageViewer.overlayKey), matching: find.byType(CustomPaint)));
    expect(night.painter!.shouldRepaint(paint.painter!), isTrue);
    expect(PageViewer.debugImageBuilds - before, 1);

    expect(r.viewer.currentPage, 19);
    expect(PageViewer.debugPrecached, containsAll(<int>[18, 20]));
    r.viewer.setPage(20, true);
    await tester.pump();
    expect(PageViewer.debugPrecached, contains(21));
    await unmount(tester);
  });

  testWidgets('a far page: the boxes wait for its image, so they never sit on another page\'s scan', (tester) async {
    final r = await data.reader(tester, audio: true, bookmarks: false);
    await pumpPhone(tester, AppShell(reader: r));
    await tester.runAsync(() => precacheImage(const AssetImage('assets/pages/page019.webp'), tester.element(find.byType(PageViewer))));
    await tester.pump();
    final state = tester.state<PageViewerState>(find.byType(PageViewer));
    expect(state.overlayPage, 19);

    r.viewer.setPage(60, true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Page 60 is not decoded yet: page 19's scan still shows, with no boxes over it.
    expect(r.viewer.currentPage, 60);
    expect(state.overlayPage, isNot(60));
    await tester.runAsync(() => precacheImage(const AssetImage('assets/pages/page060.webp'), tester.element(find.byType(PageViewer))));
    await tester.pump();
    await tester.pump();
    expect(state.overlayPage, 60);
    await unmount(tester);
  });
}

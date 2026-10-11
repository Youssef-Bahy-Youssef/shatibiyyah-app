// The view follows the recitation until the student looks elsewhere (ADR 0030):
// the wash stays with the recited verse through page turns, it lies on the
// chapter's heading while its title is recited, a verse opened from elsewhere
// does not move the recitation, and «عودة إلى البيت N» shows only while the
// recited verse is off the page on screen.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/domain/playback_engine.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/models/chapter.dart';
import 'package:shatibiyyah/models/verse.dart';
import 'package:shatibiyyah/services/data_service.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// An audio port whose position the test moves.
class _TickingAudio implements AudioPort {
  final _positions = StreamController<int>.broadcast();
  int _at = 0;
  bool _playing = false;

  /// The player reports that it stands at [ms].
  Future<void> tick(int ms) async {
    _at = ms;
    _positions.add(ms);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Stream<int> get positionMs => _positions.stream;
  @override
  int get currentPositionMs => _at;
  @override
  bool get playing => _playing;
  @override
  Stream<bool> get playingChanges => const Stream.empty();
  @override
  Future<void> seek(int ms) async => _at = ms;
  @override
  Future<void> play() async => _playing = true;
  @override
  Future<void> pause() async => _playing = false;
  @override
  Future<void> setSpeed(double speed) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory support;
  late AppContent content;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('follow_recitation_test');
    content = await AppContent.open(
      loadAsset: (key) async => ByteData.sublistView(await File(key).readAsBytes()),
      supportDir: support,
      factory: databaseFactoryFfi,
    );
  });

  tearDownAll(() async {
    await content.store.close();
    await support.delete(recursive: true);
  });

  /// The reader on [verse] with a recording whose position the test moves.
  Future<(ReaderController, _TickingAudio)> reader({int verse = 226}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.create();
    final recording = content.recordings.defaultRecording;
    final windows = await content.windowsFor(recording);
    final audio = _TickingAudio();
    final r = ReaderController(
      content: content,
      recording: recording,
      viewer: PageViewerController(legacyData(content, windows), prefs),
      engine: PlaybackEngine(audio, PlaybackPlan(windows, PlaybackScope(verse, verse), const PlaybackSettings())),
      initialVerse: verse,
    );
    addTearDown(r.dispose);
    return (r, audio);
  }

  Rect verseBox(ReaderController r, int verse) {
    final b = r.viewer.data.getBox(verse)!;
    return Rect.fromLTWH(b.x, b.y, b.w, b.h);
  }

  /// Where the wash is drawn on the page on screen, once its glide has ended.
  Rect? wash(ReaderController r) => r.viewer.playingRectAt(r.viewer.hiliteStart + 1000);

  int pageOf(int verse) => content.layout.pageOfVerse(verse);

  /// ▶, and the player's answer has reached the reader.
  Future<void> play(ReaderController r) async {
    await r.playPause();
    await Future<void>.delayed(Duration.zero);
  }

  group('the wash stays with the recited verse', () {
    test('turning away hides it and offers the way back; turning back shows it and takes the chip away', () async {
      final (r, _) = await reader();
      await play(r);
      expect((r.playing, r.detached, r.viewer.currentPage), (true, false, 19));
      expect(wash(r), verseBox(r, 226));

      r.viewer.setPage(21, true);
      await Future<void>.delayed(Duration.zero);
      expect(r.detached, isTrue);
      expect(wash(r), isNull); // page 21 has no recited verse

      r.viewer.setPage(19, true);
      await Future<void>.delayed(Duration.zero);
      expect(r.detached, isFalse, reason: 'the recited verse is on screen: nothing to come back to');
      expect(wash(r), verseBox(r, 226), reason: 'back on its page the verse is washed again');
    });

    test('the recitation moves on while the student is away: the wash waits on the verse now recited', () async {
      final (r, audio) = await reader();
      final windows = r.engine!.windows;
      await r.playScope(const PlaybackScope(226, 230));
      r.viewer.setPage(21, true);
      await Future<void>.delayed(Duration.zero);

      await audio.tick(windows.verseEnd(226)); // 226 ends; 227 is on page 19 too
      expect((r.verse, r.detached, r.viewer.currentPage), (227, true, 21), reason: 'the page on screen stays');
      expect(wash(r), isNull);

      r.viewer.setPage(19, true);
      await Future<void>.delayed(Duration.zero);
      expect(r.detached, isFalse);
      expect(wash(r), verseBox(r, 227));
    });

    test('the recitation reaches the page the student is on: the view follows again', () async {
      final first = content.layout.versesOnPage(20).first; // the verse before it ends page 19
      expect(pageOf(first - 1), 19);
      final (r, audio) = await reader(verse: first - 1);
      await r.playScope(PlaybackScope(first - 1, first + 2));
      r.viewer.setPage(20, true);
      await Future<void>.delayed(Duration.zero);
      expect(r.detached, isTrue);

      await audio.tick(r.engine!.windows.verseEnd(first - 1));
      expect((r.verse, r.detached, r.viewer.currentPage), (first, false, 20));
      // While its chapter's title is recited the wash is on the heading; then on the verse.
      await audio.tick(r.engine!.windows.cue(first) + 200);
      expect(wash(r), verseBox(r, first));
    });

    test('nothing playing: browsing shows no chip, and the verse is washed when its page is back', () async {
      final (r, _) = await reader();
      r.viewer.setPage(21, true);
      await Future<void>.delayed(Duration.zero);
      expect((r.detached, wash(r)), (false, null));
      r.viewer.setPage(19, true);
      await Future<void>.delayed(Duration.zero);
      expect((r.detached, wash(r)), (false, verseBox(r, 226)));
    });
  });

  group('a chapter\'s title being recited', () {
    test('the wash is on the heading printed on the page, then on the chapter\'s first verse', () async {
      final (r, audio) = await reader(verse: 233);
      final windows = r.engine!.windows;
      expect(windows.titleFollows(234), isTrue, reason: 'the recording speaks the title of the chapter at 235');
      final heading = r.viewer.data.chapterBox(r.viewer.data.chapterIndexForVerse(235))!;

      await r.playScope(const PlaybackScope(233, 236));
      await audio.tick(windows.verseEnd(233));
      expect((r.verse, r.inTitle, wash(r)), (234, false, verseBox(r, 234)));

      await audio.tick(windows.verseEnd(234)); // 234 ends: the title of the next chapter begins
      expect((r.verse, r.inTitle), (235, true));
      expect(wash(r), heading, reason: 'the title is recited: its heading is marked, not verse 235');

      await audio.tick(windows.cue(235) - 300); // still in the title
      expect(wash(r), heading);

      await audio.tick(windows.cue(235) + 100); // the verse itself
      expect((r.verse, r.inTitle), (235, false));
      expect(wash(r), verseBox(r, 235));
    });

    test('«تشغيل الباب» starts on the heading; a tap on a verse goes to the verse', () async {
      final (r, audio) = await reader();
      final windows = r.engine!.windows;
      final chapter = content.matn.chapterOfVerse(235);
      final heading = r.viewer.data.chapterBox(r.viewer.data.chapterIndexForVerse(235))!;
      await r.playChapter(chapter);
      await Future<void>.delayed(Duration.zero);
      expect(windows.chapterStart(235), lessThan(windows.cue(235)));
      expect((r.verse, r.inTitle, wash(r)), (235, true, heading));

      await r.tapVerse(235); // the student's jump: the verse, past its title
      await audio.tick(windows.cue(235));
      expect((r.inTitle, wash(r)), (false, verseBox(r, 235)));
    });

    test('titles turned off: the wash goes straight to the verse', () async {
      final (r, audio) = await reader(verse: 234);
      r.setPlayTitles(false);
      await r.playScope(const PlaybackScope(234, 236));
      await audio.tick(r.engine!.windows.verseEnd(234));
      expect((r.verse, r.inTitle, wash(r)), (235, false, verseBox(r, 235)));
    });
  });

  group('a verse opened from elsewhere', () {
    test('while a recitation plays it goes on: the view alone moves, and the chip leads back', () async {
      final (r, _) = await reader();
      await play(r);
      await r.goToVerse(700);
      expect((r.verse, r.engine!.plan.verse, r.playing), (226, 226, true), reason: 'the recitation did not move');
      expect((r.detached, r.browsedVerse, r.viewer.currentPage), (true, 700, pageOf(700)));
      expect(r.viewer.activeId, 226);
      expect(r.viewer.pulse!.box, verseBox(r, 700), reason: 'the verse asked for is pointed out');
      expect(wash(r), isNull);
      // The top bar names the chapter of the verse asked for, not of the page's first verse.
      expect(r.headerChapter, content.matn.chapterOfVerse(700));
      expect(r.chapter, content.matn.chapterOfVerse(226));

      r.resumeFollowing(); // «عودة إلى البيت ٢٢٦»
      expect((r.detached, r.browsedVerse, r.viewer.currentPage), (false, null, 19));
      expect(wash(r), verseBox(r, 226));
    });

    test('a verse on the page of the recited one: shown, with nothing to come back from', () async {
      final (r, _) = await reader();
      await play(r);
      await r.goToVerse(229);
      expect((r.verse, r.detached, r.browsedVerse, r.viewer.currentPage), (226, false, null, 19));
      expect(r.viewer.pulse!.box, verseBox(r, 229));
    });

    test('the recited verse itself: the view returns to it', () async {
      final (r, _) = await reader();
      await play(r);
      r.viewer.setPage(30, true);
      await Future<void>.delayed(Duration.zero);
      await r.goToVerse(226);
      expect((r.detached, r.viewer.currentPage), (false, 19));
    });

    test('nothing playing: the reader moves to the verse', () async {
      final (r, _) = await reader();
      await r.goToVerse(700);
      expect((r.verse, r.detached, r.viewer.currentPage), (700, false, pageOf(700)));
      expect(wash(r), verseBox(r, 700));
    });

    test('a tap on a verse of the page browsed to moves the recitation there', () async {
      final (r, _) = await reader();
      await play(r);
      await r.goToVerse(700);
      await r.tapVerse(701);
      expect((r.verse, r.engine!.plan.verse, r.detached, r.browsedVerse), (701, 701, false, null));
    });
  });

  group('the page viewer', () {
    Verse v(int id, int page) => Verse(id: id, page: page, x: 0, y: 100.0 * id, width: 900, height: 70);

    Future<PageViewerController> viewer() async {
      SharedPreferences.setMockInitialValues({});
      final data = ShatibiyyahData([v(1, 1), v(2, 2), v(3, 2)], [null, null, null, null], const [
        Chapter(name: 'أ', startVerse: 1, endVerse: 1, verseCount: 1, startTime: null,
            page: 1, x: 0, y: 0, width: 900, height: 80),
        // Its heading is printed at the foot of page 1; its first verse opens page 2.
        Chapter(name: 'ب', startVerse: 2, endVerse: 2, verseCount: 1, startTime: null,
            page: 1, x: 0, y: 1600, width: 900, height: 80),
        Chapter(name: 'ج', startVerse: 3, endVerse: 3, verseCount: 1, startTime: null), // no heading
      ], durationSeconds: 0);
      return PageViewerController(data, await Prefs.create());
    }

    Rect? wash(PageViewerController c) => c.playingRectAt(c.hiliteStart + 1000);

    test('a heading on the page before its first verse: the title is shown there, the verse on its own page', () async {
      final c = await viewer();
      c.setActiveVerse(1);
      c.setActiveVerse(2, title: true);
      expect((c.currentPage, wash(c)), (1, const Rect.fromLTWH(0, 1600, 900, 80)));
      c.setActiveVerse(2);
      expect((c.currentPage, wash(c)), (2, const Rect.fromLTWH(0, 200, 900, 70)));
    });

    test('a chapter with no printed heading, or a verse inside a chapter: the verse is marked', () async {
      final c = await viewer();
      c.setActiveVerse(3, title: true);
      expect((c.currentPage, wash(c)), (2, const Rect.fromLTWH(0, 300, 900, 70)));
    });

    test('without follow the page on screen stays, and the mark waits on its page', () async {
      final c = await viewer();
      c.setActiveVerse(1);
      c.setActiveVerse(3, follow: false);
      expect((c.currentPage, c.activeId, c.activePage, wash(c)), (1, 3, 2, null));
      c.setPage(2, true);
      expect(wash(c), const Rect.fromLTWH(0, 300, 900, 70));
      expect(c.prevBox, isNull, reason: 'the wash does not glide in from another page');
    });

    test('showVerse turns to a verse and pulses it; the mark stays where it was', () async {
      final c = await viewer();
      c.setActiveVerse(1);
      c.showVerse(3);
      expect((c.currentPage, c.activeId, c.activePage), (2, 1, 1));
      expect(c.pulse!.box, const Rect.fromLTWH(0, 300, 900, 70));
      expect(wash(c), isNull);
    });
  });
}

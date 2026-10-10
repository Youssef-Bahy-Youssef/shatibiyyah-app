// «تابع», the home-screen widget (plan 6.1, ADRs 0017 and 0025): what the app
// publishes to it, how often, and what the widget's taps do to the reader.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/app/widgets.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/data/settings_store.dart';
import 'package:shatibiyyah/domain/playback_engine.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/services/lock_screen.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _SilentAudio implements AudioPort {
  bool _playing = false;
  @override
  Stream<int> get positionMs => const Stream.empty();
  @override
  Stream<bool> get playingChanges => const Stream.empty();
  @override
  int get currentPositionMs => 0;
  @override
  bool get playing => _playing;
  @override
  Future<void> seek(int ms) async {}
  @override
  Future<void> play() async => _playing = true;
  @override
  Future<void> pause() async => _playing = false;
  @override
  Future<void> setSpeed(double speed) async {}
}

/// The platform side, recorded.
class _Port implements WidgetPort {
  final List<Map<String, dynamic>> published = [];
  List<WidgetRequest> pending = [];
  final StreamController<WidgetRequest> incoming = StreamController.broadcast(sync: true);

  @override
  Future<void> publish(String state) async => published.add(json.decode(state) as Map<String, dynamic>);
  @override
  Future<List<WidgetRequest>> takePending() async {
    final p = pending;
    pending = [];
    return p;
  }

  @override
  Stream<WidgetRequest> get requests => incoming.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory support;
  late AppContent content;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('home_widgets_test');
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

  Future<ReaderController> reader({bool audio = true, int verse = 226}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await Prefs.create();
    final recording = content.recordings.defaultRecording;
    final windows = await content.windowsFor(recording);
    return ReaderController(
      content: content,
      recording: recording,
      viewer: PageViewerController(legacyData(content, windows), prefs),
      engine: audio
          ? PlaybackEngine(_SilentAudio(), PlaybackPlan(windows, const PlaybackScope(226, 234), const PlaybackSettings()))
          : null,
      store: SettingsStore(prefs),
      initialVerse: verse,
    );
  }

  group('what «تابع» is told', () {
    test('the verse, whether it is being recited, the recording and the theme', () async {
      final r = await reader();
      expect(resumeWidgetState(r).toJson(), {
        'v': 1,
        'verse': 226,
        'playing': false,
        'audio': true,
        'recording': r.recording.id,
        'theme': 'auto',
      });

      await r.playPause();
      await Future<void>.delayed(Duration.zero);
      expect(resumeWidgetState(r).playing, isTrue);

      await r.next();
      await Future<void>.delayed(Duration.zero);
      expect(resumeWidgetState(r).verse, 227);

      r.setThemeChoice(ThemeChoice.paper);
      expect(resumeWidgetState(r).theme, 'paper');
      r.setThemeChoice(ThemeChoice.night);
      expect(resumeWidgetState(r).theme, 'night');
    });

    test('with no recording on the device it says so, and is never "playing"', () async {
      final state = resumeWidgetState(await reader(audio: false, verse: 1));
      expect(state.audio, isFalse);
      expect(state.playing, isFalse);
      expect(state.verse, 1);
    });

    test('it carries no content: no verse text, no chapter name, no reciter name', () async {
      // The widget reads those from the content snapshot itself (ADR 0001).
      final keys = resumeWidgetState(await reader()).toJson().keys.toSet();
      expect(keys, {'v', 'verse', 'playing', 'audio', 'recording', 'theme'});
    });
  });

  group('publishing', () {
    test('the state goes out when the widgets start, and again only when it changes', () async {
      final r = await reader();
      final port = _Port();
      final widgets = HomeWidgets(port: port, reader: r, open: (_) {});
      await widgets.start();
      expect(port.published, hasLength(1));
      expect(port.published.single['verse'], 226);

      r.openMenu(226); // the reader notifies, but nothing the widget shows has changed
      r.closeMenu();
      await Future<void>.delayed(Duration.zero);
      expect(port.published, hasLength(1));
      widgets.dispose();
    });

    test('six changes in five seconds publish once more, at the end of the five seconds, with the last one', () async {
      final r = await reader(); // real file work, so before the fake clock
      fakeAsync((async) {
        final port = _Port();
        final widgets = HomeWidgets(port: port, reader: r, open: (_) {});
        widgets.start();
        async.flushMicrotasks();
        expect(port.published, hasLength(1)); // the first state, at once

        for (var i = 0; i < 6; i++) {
          r.tapVerse(227 + i);
          async.elapse(const Duration(milliseconds: 800));
        }
        expect(port.published, hasLength(1), reason: 'nothing more inside the five seconds');

        async.elapse(const Duration(milliseconds: 200)); // 5.0 s after the first
        expect(port.published, hasLength(2));
        expect(port.published.last['verse'], 232, reason: 'the last state wins');

        async.elapse(const Duration(seconds: 30)); // and no timer keeps running
        expect(port.published, hasLength(2));
        expect(async.pendingTimers, isEmpty);
        widgets.dispose();
      });
    });

    test('a change after a quiet five seconds goes out at once', () async {
      final r = await reader(); // real file work, so before the fake clock
      fakeAsync((async) {
        final port = _Port();
        final widgets = HomeWidgets(port: port, reader: r, open: (_) {});
        widgets.start();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 6));
        r.tapVerse(230);
        async.flushMicrotasks();
        expect(port.published, hasLength(2));
        expect(port.published.last['verse'], 230);
        widgets.dispose();
      });
    });

    test('a change that is undone inside the five seconds publishes nothing', () async {
      final r = await reader(); // real file work, so before the fake clock
      fakeAsync((async) {
        final port = _Port();
        final widgets = HomeWidgets(port: port, reader: r, open: (_) {});
        widgets.start();
        async.flushMicrotasks();
        r.tapVerse(230);
        r.tapVerse(226);
        async.elapse(const Duration(seconds: 6));
        expect(port.published, hasLength(1));
        widgets.dispose();
      });
    });

    test('leaving the app tells the widget at once, inside the five seconds', () async {
      final r = await reader(); // real file work, so before the fake clock
      fakeAsync((async) {
        final port = _Port();
        final widgets = HomeWidgets(port: port, reader: r, open: (_) {});
        widgets.start();
        async.flushMicrotasks();
        r.tapVerse(230);
        async.elapse(const Duration(seconds: 1));
        expect(port.published, hasLength(1));

        widgets.publishNow(); // the app goes to the background
        expect(port.published, hasLength(2));
        expect(port.published.last['verse'], 230);

        async.elapse(const Duration(seconds: 10)); // the end of the five seconds has nothing new to say
        expect(port.published, hasLength(2));
        widgets.publishNow();
        expect(port.published, hasLength(2), reason: 'nothing changed');
        widgets.dispose();
      });
    });

    test('after dispose nothing more is published', () async {
      final r = await reader(); // real file work, so before the fake clock
      fakeAsync((async) {
        final port = _Port();
        final widgets = HomeWidgets(port: port, reader: r, open: (_) {});
        widgets.start();
        async.flushMicrotasks();
        r.tapVerse(230);
        widgets.dispose();
        async.elapse(const Duration(seconds: 6));
        expect(port.published, hasLength(1));
        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  group('the widget\'s taps', () {
    test('▶ plays and ❚❚ pauses; each says what it wants, so a stale button cannot do the opposite', () async {
      final r = await reader();
      final port = _Port();
      final widgets = HomeWidgets(port: port, reader: r, open: (_) {});
      await widgets.start();

      port.incoming.add(const WidgetRequest.play());
      await Future<void>.delayed(Duration.zero);
      expect(r.playing, isTrue);
      port.incoming.add(const WidgetRequest.play()); // the widget still showed ▶
      await Future<void>.delayed(Duration.zero);
      expect(r.playing, isTrue);

      port.incoming.add(const WidgetRequest.pause());
      await Future<void>.delayed(Duration.zero);
      expect(r.playing, isFalse);
      port.incoming.add(const WidgetRequest.pause());
      await Future<void>.delayed(Duration.zero);
      expect(r.playing, isFalse);
      widgets.dispose();
    });

    test('▶ pressed while the app was not running plays once the reader is up', () async {
      final r = await reader();
      final port = _Port()..pending = [const WidgetRequest.play()];
      final widgets = HomeWidgets(port: port, reader: r, open: (_) {});
      await widgets.start();
      await Future<void>.delayed(Duration.zero);
      expect(r.playing, isTrue);
      // It is handled before the first state goes out, so the widget is not told
      // "paused" and then left with it for five seconds.
      expect(port.published, hasLength(1));
      expect(port.published.single['playing'], isTrue);
      widgets.dispose();
    });

    test('a tap on the verse and a tap on «تنزيل» are handed to the app to open', () async {
      final r = await reader();
      final opened = <WidgetRequest>[];
      final port = _Port()..pending = [const WidgetRequest.openVerse(226)];
      final widgets = HomeWidgets(port: port, reader: r, open: opened.add);
      await widgets.start();
      port.incoming.add(const WidgetRequest.openDownloads());
      await Future<void>.delayed(Duration.zero);
      expect(opened, [const WidgetRequest.openVerse(226), const WidgetRequest.openDownloads()]);
      expect(r.playing, isFalse);
      widgets.dispose();
    });

    test('a request the platform sends is read from its name', () {
      expect(WidgetRequest.parse({'do': 'play'}), const WidgetRequest.play());
      expect(WidgetRequest.parse({'do': 'pause'}), const WidgetRequest.pause());
      expect(WidgetRequest.parse({'do': 'verse', 'verse': 226}), const WidgetRequest.openVerse(226));
      expect(WidgetRequest.parse({'do': 'downloads'}), const WidgetRequest.openDownloads());
      expect(WidgetRequest.parse({'do': 'verse'}), isNull);
      expect(WidgetRequest.parse({'do': 'dance'}), isNull);
      expect(WidgetRequest.parse(null), isNull);
    });
  });

  group('the lock-screen handler before the reader is up', () {
    // The widget's ▶ starts the app's engine with no screen; the session's own play can
    // arrive before the reader is attached.
    test('play is remembered and happens when the reader attaches', () async {
      final handler = LockScreenHandler();
      await handler.play();
      final r = await reader();
      handler.attach(r);
      await Future<void>.delayed(Duration.zero);
      expect(r.playing, isTrue);
    });

    test('play then pause before the reader attaches leaves it paused', () async {
      final handler = LockScreenHandler();
      await handler.play();
      await handler.pause();
      final r = await reader();
      handler.attach(r);
      await Future<void>.delayed(Duration.zero);
      expect(r.playing, isFalse);
    });
  });
}

// ignore_for_file: invalid_use_of_visible_for_testing_member
// Golden images of the v3 reader in each of its states (P4 acceptance: every reader
// state, both themes, both sizes), rendered with the real fonts, icons and pages.
//
//   flutter test test_goldens                    # compare
//   flutter test test_goldens --update-goldens   # accept the current rendering
//
// Goldens depend on the platform and the Flutter version (text rasterization), so
// they live outside test/ and plain `flutter test` does not run them; these were
// made on macOS with Flutter 3.44. `tool/check.sh --goldens` runs them.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/data/settings_store.dart';
import 'package:shatibiyyah/domain/playback_engine.dart';
import 'package:shatibiyyah/domain/playback_plan.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/design/app_theme.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/reader/reader_screen.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _SilentAudio implements AudioPort {
  bool _playing = false;
  @override
  Stream<int> get positionMs => const Stream.empty();
  @override
  int get currentPositionMs => 0;
  @override
  bool get playing => _playing;
  @override
  Stream<bool> get playingChanges => const Stream.empty();
  @override
  Future<void> seek(int ms) async {}
  @override
  Future<void> play() async => _playing = true;
  @override
  Future<void> pause() async => _playing = false;
  @override
  Future<void> setSpeed(double speed) async {}
}

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> assets) async {
    final loader = FontLoader(name);
    for (final a in assets) {
      loader.addFont(rootBundle.load(a));
    }
    await loader.load();
  }

  await family('ScheherazadeNew', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/ScheherazadeNew-$w.ttf',
  ]);
  await family('ReemKufi', ['assets/fonts/ReemKufi.ttf']);
  await family('packages/lucide_icons_flutter/Lucide', ['packages/lucide_icons_flutter/assets/lucide.ttf']);
}

/// A reader state: what to do to a fresh reader (on verse 226, page 19) before the shot.
typedef _Setup = void Function(ReaderController r, AppContent content);

final Map<String, _Setup> _states = {
  'page': (_, _) {},
  'chrome_hidden': (r, _) => r.toggleChrome(),
  'menu': (r, _) => r.openMenu(229),
  'text_mode': (r, _) => r.setTextMode(true),
  'selection': (r, _) {
    r.startSelection(226);
    r.tapVerse(229);
  },
  'heading': (r, c) => r.openHeading(c.matn.chapters.indexWhere((ch) => ch.fromVerse == 226)),
  'playing': (r, _) => r.playScope(const PlaybackScope(226, 234)),
};

void main() {
  sqfliteFfiInit();
  late Directory support;
  late AppContent content;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
    support = await Directory.systemTemp.createTemp('reader_goldens');
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

  const sizes = {
    '390x844': (Size(390, 844), FakeViewPadding(top: 47, bottom: 34)),
    '360x640': (Size(360, 640), FakeViewPadding(top: 24, bottom: 16)),
  };

  for (final (size, theme) in [('390x844', ReaderTheme.dark), ('390x844', ReaderTheme.paper), ('360x640', ReaderTheme.dark)]) {
    for (final MapEntry(key: state, value: setup) in _states.entries) {
      final name = '${state}_${theme.name}_$size';
      testWidgets(name, (tester) async {
        final (screen, padding) = sizes[size]!;
        tester.view.physicalSize = screen;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = padding;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({});

        late ReaderController r;
        await tester.runAsync(() async {
          final prefs = await Prefs.create();
          final recording = content.recordings.defaultRecording;
          final windows = await content.windowsFor(recording);
          r = ReaderController(
            content: content,
            recording: recording,
            windows: windows,
            viewer: PageViewerController(legacyData(content, windows), prefs),
            engine: state == 'playing'
                ? PlaybackEngine(_SilentAudio(), PlaybackPlan(windows, const PlaybackScope(226, 234), const PlaybackSettings()))
                : null,
            initialVerse: 226,
          );
        });
        r.setTheme(theme);
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: theme == ReaderTheme.paper ? Brightness.light : Brightness.dark,
            fontFamily: 'ScheherazadeNew',
            extensions: [colorsFor(theme)],
          ),
          // Reduced motion, as a user can ask for: the playing shamsa stops spinning, so
          // the image does not depend on how far a rotation had got.
          builder: (context, child) =>
              MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
          home: ReaderScreen(reader: r),
        ));
        // The scanned page is an asset image: decode it for real, then draw.
        await tester.runAsync(() => precacheImage(
              const AssetImage('assets/pages/page019.webp'),
              tester.element(find.byType(ReaderScreen)),
            ));
        setup(r, content);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 60)); // chrome fades, text-mode scroll
        }
        await expectLater(find.byType(ReaderScreen), matchesGoldenFile('goldens/$name.png'));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3)); // let notices and animations end
      });
    }
  }
}

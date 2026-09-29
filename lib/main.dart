// === PWA INVENTORY ===
// Screens (single-screen app, two regions + overlays):
//   - Page viewer (scanned manuscript pages 1–94 + canvas highlight overlay)
//   - Controls panel: desktop = right side panel; mobile = immersive chrome
//     (top toolbar + bottom range-status card + mini audio bar) over a full-screen page
//   - Overlays/sheets: console sheet (cp-full), picker sheet (pause/speed/verse/section),
//     settings sheet (night/brightness/page-cache), range selector sheet (باب/نطاق/كل المتن),
//     full-screen verse search overlay, chapter-action band, resume chip, session chip, splash.
// State variables (audio.js + page-viewer.js + app.js, all persisted to localStorage):
//   mode(chapter|range|full), chapterIdx, fromVerse, toVerse, verseRepsTotal, sectionRepsTotal,
//   speed, pauseSeconds, currentVerse, rangeStart/EndVerse, rangeStart/EndTime, verseRepsLeft,
//   sectionRepsLeft, atEndGuard, scrubbing, selectedChapterName; viewer: zoom, tx, ty,
//   currentPage, activeId, activeBox, prevBox, pulse, chapterSel, chapterHover, night,
//   brightnessPct, showBoxes; app: barState, detached, chapterProgress map, last_session,
//   keepControlsVisible, controlsHidden, immersiveHintShown.
// User interactions: play/pause/stop/prev/next; tap verse → seek; tap chapter header → select
//   → Play-Chapter band; swipe L/R → page turn; pinch-zoom; double-tap zoom; pan + momentum;
//   scrubber drag (live verse preview); mini-scrub; mode tabs; chapter list tap; range steppers
//   & number inputs; picker chips; night toggle; brightness slider; show-boxes toggle; search
//   (diacritic-insensitive, chapters+verses); resume chip; session chip; keep-controls toggle;
//   single empty-tap → toggle immersive chrome.
// Audio behaviors (audio.js, ported verbatim): CBR frame-accurate seek; eps() boundary lead
//   = max(.14, rate*.16); verse repeat (REP_OPTS incl ∞); section repeat; inter-verse pause
//   (PAUSE_OPTS); speed (SPEED_OPTS, preservesPitch); setupRange for chapter/range/full;
//   onBoundary→advance/repeat; reachRangeEnd→loop or park+pause; tick via positionStream+16ms
//   timer; seekToVerse/Time/Fraction; togglePlay smart-restart; previewVerseAt; media session.
// Data (since 2026-09-29): assets/content/content.sqlite, built by `spd app-snapshot`, read
//   through lib/data/ (the PWA's verses.json / chapters.json / timestamps.json /
//   shatibiyyah.txt / xing-toc.json are retired; lib/data/legacy_adapter.dart feeds the old
//   screens). No audio is bundled: a recording plays from a file on the device.
// Assets: 94 page WebPs (page001–094, 1130×1735) + page_cover.webp; icons
//   icon.png/icon-192.png/icon-maskable.png; fonts ScheherazadeNew (naskh) + ReemKufi (kufi).
// CSS colors (style.css :root): darker #965f0d, base/gold #ffab2e, lighter/goldBright #fadbae,
//   accent #4314ff, dark #4e3613, light #f4f1eb, ink #1b1307, ink2 #241a0c, panel #2a1e0e,
//   panel2 #33260f, raised #3f2f15, line #4a3719, lineSoft #382912, parch #f4f1eb,
//   parchDim #d6ccb8, muted #b39a6b, muted2 #8d7850, teal #86b07a, danger #e08a5a, onGold #1a1304.
//   highlight day rgba(255,171,46,.32/.95/.18); night rgba(120,140,250,.30)/(170,186,255,.95)/(150,168,255,.18).
// CSS fonts: --ff-naskh "Scheherazade New" · --ff-kufi "Reem Kufi" · --ff-ui system. Sizes in
//   rem (1rem=16px) ported 1:1; radii --r-lg 22 / --r-md 16 / --r-sm 12; --tap 52.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_controller.dart';
import 'data/app_content.dart';
import 'data/legacy_adapter.dart';
import 'data/legacy_prefs.dart';
import 'data/recording_repository.dart';
import 'services/audio_service.dart';
import 'services/preferences_service.dart';
import 'services/sync_service.dart';
import 'theme.dart';
import 'ui/home_screen.dart';
import 'ui/widgets/page_viewer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock-screen / background-audio support. Never let an init failure here blank the
  // whole app — the in-app player works regardless.
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'app.shatibiyyah.hirz.channel.audio',
      androidNotificationChannelName: 'تيسير الشاطبية',
      androidNotificationOngoing: true,
    );
  } catch (_) {}
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ShatibiyyahApp());
}

class ShatibiyyahApp extends StatelessWidget {
  const ShatibiyyahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'تيسير الشاطبية',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: C.ink,
        fontFamily: kFontNaskh,
        colorScheme: const ColorScheme.dark(
          surface: C.ink,
          primary: C.gold,
          secondary: C.goldBright,
          onPrimary: C.onGold,
          error: C.danger,
        ),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const _Boot(),
    );
  }
}

/// Boot sequence — port of app.js main(): load data + verse text in parallel, build the
/// engine/viewer/sync, then run the splash (≥1200ms) over the cover image.
class _Boot extends StatefulWidget {
  const _Boot();
  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  AppController? _app;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final content = await AppContent.open();
      final prefs = await Prefs.create();
      migrateLegacyPrefs(prefs, content.matn);
      final recording = content.recordings.defaultRecording;
      final data = legacyData(content, await content.windowsFor(recording));
      final verseText = legacyVerseText(content);
      final player = AudioPlayer();
      final audio = AudioEngine(player, data, prefs);
      final viewer = PageViewerController(data, prefs);
      final sync = SyncController(audio, viewer, data);
      final app = AppController(
        content: content,
        recording: recording,
        audioFilePath: await _localAudio(recording),
        data: data,
        verseText: verseText,
        audio: audio,
        viewer: viewer,
        sync: sync,
        prefs: prefs,
      );
      if (mounted) setState(() => _app = app);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  /// The recording's file if it is on the device and complete (the download manager's
  /// target; side-loaded in development). Nothing is bundled.
  Future<String?> _localAudio(Recording recording) async {
    final support = await getApplicationSupportDirectory();
    final file = File(p.join(support.path, RecordingRepository.localFileName(recording)));
    if (await file.exists() && await file.length() == recording.audioBytes) return file.path;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return _Splash(
      ready: _app != null || _error,
      child: _app != null
          ? HomeScreen(app: _app!)
          : (_error ? const _ErrorScreen() : const SizedBox.shrink()),
    );
  }
}

/// Splash — port of index.html inline splash: paper background, cover image, ≥1200ms min,
/// fade out over 400ms. The cover is always shown on paper (never inverted).
class _Splash extends StatefulWidget {
  final bool ready;
  final Widget child;
  const _Splash({required this.ready, required this.child});
  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> {
  bool _minElapsed = false;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _minElapsed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dismissed = widget.ready && _minElapsed;
    // Keep `widget.child` (HomeScreen) at a STABLE position in the tree so its State is
    // never re-created when the splash is removed. Returning the child directly here used
    // to move it out of the Stack, remounting HomeScreen and running boot() (and the 142MB
    // audio load) a second time. Now the child always stays at index 0 and only the splash
    // overlay is added/removed.
    return Stack(
      children: [
        widget.child,
        if (!(dismissed && _gone))
          AnimatedOpacity(
            opacity: dismissed ? 0 : 1,
            duration: const Duration(milliseconds: 400),
            onEnd: () {
              if (dismissed && mounted) setState(() => _gone = true);
            },
            child: Container(
              color: C.colorLight, // --color-light #f4f1eb (paper)
              alignment: Alignment.center,
              child: FractionallySizedBox(
                widthFactor: 0.85,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x884E3613),
                          blurRadius: 48,
                          offset: Offset(0, 18),
                          spreadRadius: -12,
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/pages/page_cover.webp',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.ink,
      body: Center(
        child: Text(
          'تعذّر تحميل البيانات',
          style: naskh(size: 20, color: C.parch),
        ),
      ),
    );
  }
}

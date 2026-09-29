// lib/ui/reader/reader_controller.dart — state of the v3 reader.
//
// Owns what the reader shows and plays: the current verse, whether the view
// follows playback or the student has browsed away (the «عودة إلى البيت N» chip),
// the chrome (top bar + player, faded in and out without moving the page), and
// the verse menu. Playback runs on the rule-tested PlaybackPlan/PlaybackEngine
// over just_audio; with no recording on the device there is no engine and the
// player says so. Page drawing reuses PageViewerController.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/app_content.dart';
import '../../data/matn_repository.dart';
import '../../data/recording_repository.dart';
import '../../data/settings_store.dart';
import '../../data/user_store.dart';
import '../../domain/playback_engine.dart';
import '../../domain/playback_plan.dart';
import '../../domain/playback_windows.dart';
import '../design/app_theme.dart';
import '../widgets/page_viewer.dart';

/// How long a notice such as «بدأ باب جديد» stays (the prototype's toast).
const Duration kNoticeDuration = Duration(seconds: 2);

class ReaderController extends ChangeNotifier {
  final AppContent content;
  final Recording recording;
  final PlaybackWindows windows;
  final PageViewerController viewer;
  final UserStore? user;
  final SettingsStore? store;

  /// Null until the recording is on the device.
  final PlaybackEngine? engine;

  PlaybackSettings _settings;
  double _speed = 1;

  int _verse;
  bool _textMode = false;
  double _textScale = 1;
  bool _detached = false;
  bool _chromeVisible = true;
  int? _menuVerse;
  int? _heading; // the chapter whose heading was tapped (its card is open)
  String? _notice; // a short notice, e.g. «بدأ باب جديد · …»
  Timer? _noticeTimer;
  int? _selectionStart; // «بداية نطاق»
  int? _selectionEnd; // the verse tapped after it
  EngineState? _engineState;
  final List<StreamSubscription<dynamic>> _subs = [];

  ReaderController({
    required this.content,
    required this.recording,
    required this.windows,
    required this.viewer,
    this.engine,
    this.user,
    this.store,
    PlaybackSettings initialSettings = const PlaybackSettings(),
    int initialVerse = 1,
  })  : _verse = initialVerse,
        _settings = initialSettings {
    final s = store;
    if (s != null) {
      _settings = _settings.copyWith(
        verseRepeats: s.verseRepeats,
        sectionRepeats: s.sectionRepeats,
        gapMs: s.gapMs,
        playTitles: s.playTitles,
      );
      _speed = s.speedFor(recording.id);
      _textMode = s.textMode;
      _textScale = s.textScale;
      appTheme.value = s.theme;
    }
    engine?.plan.settings = _settings;
    engine?.audio.setSpeed(_speed);
    _subs.add(viewer.onVerseTap.listen(tapVerse));
    _subs.add(viewer.onVerseLongPress.listen(openMenu));
    _subs.add(viewer.onPageTap.listen((_) => toggleChrome()));
    _subs.add(viewer.onPageChange.listen((_) => _onPageSwiped()));
    _subs.add(viewer.onChapterTap.listen(openHeading));
    final e = engine;
    if (e != null) _subs.add(e.states.listen(_onEngineState));
    viewer.setActiveVerse(_verse);
  }

  // ── what the UI reads ──
  int get verse => _verse;
  MatnChapter get chapter => content.matn.chapterOfVerse(_verse);
  int get page => viewer.currentPage;
  bool get audioAvailable => engine != null;
  bool get playing => _engineState?.playing ?? false;
  bool get detached => _detached;
  bool get chromeVisible => _chromeVisible;
  int? get menuVerse => _menuVerse;

  /// The chapter whose heading card is open (tapped on the page), if any.
  MatnChapter? get headingChapter => _heading == null ? null : content.matn.chapters[_heading!];

  /// A short notice over the page (shown for [kNoticeDuration]).
  String? get notice => _notice;

  /// Selecting: a start is set; the range exists once a second verse is tapped.
  bool get selecting => _selectionStart != null;

  /// The selected run, lowest verse first (just the start until a second tap).
  ({int from, int to})? get selection {
    final a = _selectionStart;
    if (a == null) return null;
    final b = _selectionEnd ?? a;
    return (from: a < b ? a : b, to: a < b ? b : a);
  }

  /// Whether the run is complete (the selection bar replaces the player).
  bool get selectionComplete => _selectionEnd != null;
  int get verseRepetition => _engineState?.verseRepetition ?? 1;
  int get sectionRepetition => _engineState?.sectionRepetition ?? 1;
  bool get inTitle => _engineState?.inTitle ?? false;

  /// The chapter shown in the top bar: the playing verse's, or the page's when browsing.
  MatnChapter get headerChapter {
    // Following (or browsing back to the verse's own page): the current verse's chapter.
    if (!_detached && content.layout.pageOfVerse(_verse) == page) return chapter;
    final onPage = content.layout.versesOnPage(page);
    return onPage.isEmpty ? chapter : content.matn.chapterOfVerse(onPage.first);
  }

  // ── settings (tools sheet) ──
  PlaybackSettings get settings => _settings;
  double get speed => _speed;
  ReaderTheme get theme => appTheme.value;
  bool get textMode => _textMode;
  double get textScale => _textScale;
  bool get night => viewer.night;
  int get brightness => viewer.brightnessPct;

  void _apply(PlaybackSettings s) {
    _settings = s;
    engine?.plan.settings = s;
    notifyListeners();
  }

  void setVerseRepeats(int? n) {
    store?.verseRepeats = n;
    _apply(_settings.copyWith(verseRepeats: n));
  }

  void setSectionRepeats(int? n) {
    store?.sectionRepeats = n;
    _apply(_settings.copyWith(sectionRepeats: n));
  }

  void setGap(int ms) {
    store?.gapMs = ms;
    _apply(_settings.copyWith(gapMs: ms));
  }

  void setPlayTitles(bool on) {
    store?.playTitles = on;
    _apply(_settings.copyWith(playTitles: on));
  }

  void setSpeed(double v) {
    _speed = v;
    store?.setSpeedFor(recording.id, v);
    engine?.audio.setSpeed(v);
    notifyListeners();
  }

  void setTheme(ReaderTheme t) {
    store?.theme = t;
    appTheme.value = t;
    notifyListeners();
  }

  /// Text mode keeps the top bar and the player on screen: there is no page to uncover.
  void setTextMode(bool on) {
    _textMode = on;
    store?.textMode = on;
    _menuVerse = null;
    if (on) _chromeVisible = true;
    notifyListeners();
  }

  void setTextScale(double v) {
    _textScale = v.clamp(0.75, 2).toDouble();
    store?.textScale = _textScale;
    notifyListeners();
  }

  void setNight(bool on) {
    viewer.setNightMode(on);
    notifyListeners();
  }

  void setBrightness(int pct) {
    viewer.setBrightness(pct);
    notifyListeners();
  }

  // ── transport ──
  PlaybackScope _chapterScope(int verse) {
    final c = content.matn.chapterOfVerse(verse);
    return PlaybackScope(c.fromVerse, c.toVerse);
  }

  Future<void> playPause() async {
    final e = engine;
    if (e == null) return;
    if (playing) {
      await e.pause();
    } else {
      _detached = false;
      viewer.setActiveVerse(_verse);
      if (_engineState == null || _engineState!.finished || e.plan.verse != _verse) {
        e.plan.scope = _chapterScope(_verse);
        await e.play(_verse);
      } else {
        await e.resume();
      }
    }
    notifyListeners();
  }

  /// «الاستماع إلى؟»: play [scope] from its first verse.
  Future<void> playScope(PlaybackScope scope) async {
    final e = engine;
    if (e == null) return;
    _menuVerse = null;
    _verse = scope.fromVerse;
    _detached = false;
    viewer.setActiveVerse(_verse);
    e.plan.scope = scope;
    notifyListeners();
    await e.play(scope.fromVerse);
  }

  /// «إيقاف والعودة إلى البداية»: stop and go back to the start of the current scope.
  Future<void> stop() async {
    final e = engine;
    if (e == null) return;
    await e.pause();
    await tapVerse(e.plan.scope.fromVerse);
  }

  Future<void> next() => _step(1);
  Future<void> previous() => _step(-1);

  Future<void> _step(int direction) async {
    final target = (_verse + direction).clamp(1, content.matn.lastVerse);
    await tapVerse(target);
  }

  /// A tap on a verse moves playback (or, without audio, the reader) to it. While
  /// selecting, it sets the end of the run instead (again to extend or shrink it).
  Future<void> tapVerse(int verse) async {
    closeMenu();
    closeHeading();
    if (selecting) {
      _selectionEnd = verse;
      _showSelection();
      return;
    }
    _verse = verse;
    _detached = false;
    viewer.setActiveVerse(verse);
    final e = engine;
    if (e != null && playing) {
      final scope = e.plan.scope;
      if (verse < scope.fromVerse || verse > scope.toVerse) e.plan.scope = _chapterScope(verse);
      await e.jumpTo(verse);
    }
    notifyListeners();
  }

  // ── following playback ──
  void _onEngineState(EngineState s) {
    final changed = s.verse != _verse;
    _engineState = s;
    // Playback itself crossing into a new chapter (a jump sets _verse first, so never here).
    if (changed && s.playing && content.matn.chapterOfVerse(s.verse).id != chapter.id) {
      _showNotice('بدأ باب جديد · ${content.matn.chapterOfVerse(s.verse).title}');
    }
    if (changed) {
      _verse = s.verse;
      if (!_detached) viewer.setActiveVerse(s.verse);
    }
    notifyListeners();
  }

  void _onPageSwiped() {
    // Browsing away while audio plays detaches the view (the chip offers the way back).
    if (playing && content.layout.pageOfVerse(_verse) != page) _detached = true;
    notifyListeners(); // the top bar shows the page on screen and its chapter
  }

  /// «عودة إلى البيت N».
  void resumeFollowing() {
    _detached = false;
    viewer.setActiveVerse(_verse);
    notifyListeners();
  }

  void _showNotice(String text) {
    _notice = text;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(kNoticeDuration, () {
      _notice = null;
      notifyListeners();
    });
    notifyListeners();
  }

  // ── chapter heading (features-v3 chapter-header-tap) ──
  /// A tap on a chapter heading drawn on the page: outline it and open its card.
  void openHeading(int chapterIndex) {
    if (selecting) return;
    _menuVerse = null;
    _heading = chapterIndex;
    viewer.setSelectedChapter(chapterIndex);
    notifyListeners();
  }

  void closeHeading() {
    if (_heading == null) return;
    _heading = null;
    viewer.setSelectedChapter(null);
    notifyListeners();
  }

  /// «تشغيل الباب»: the chapter from its spoken title.
  Future<void> playChapter(MatnChapter c) async {
    closeHeading();
    await playScope(PlaybackScope(c.fromVerse, c.toVerse, fromChapterTitle: true));
  }

  // ── selection (features-v3 multi-verse-selection) ──
  /// «بداية نطاق»: [verse] starts a run; the next verse tapped ends it.
  void startSelection(int verse) {
    _menuVerse = null;
    _selectionStart = verse;
    _selectionEnd = null;
    _chromeVisible = true;
    _showSelection();
  }

  /// «الباب كاملًا»: the whole chapter of the run's start.
  void selectChapter() {
    final start = _selectionStart;
    if (start == null) return;
    final c = content.matn.chapterOfVerse(start);
    _selectionStart = c.fromVerse;
    _selectionEnd = c.toVerse;
    _showSelection();
  }

  void clearSelection() {
    if (_selectionStart == null) return;
    _selectionStart = null;
    _selectionEnd = null;
    _showSelection();
  }

  /// «تشغيل»: play the run, then leave selection.
  Future<void> playSelection() async {
    final s = selection;
    if (s == null) return;
    clearSelection();
    await playScope(PlaybackScope(s.from, s.to));
  }

  void _showSelection() {
    viewer.setSelection(selection);
    notifyListeners();
  }

  // ── chrome and menu ──
  void toggleChrome() {
    if (_menuVerse != null) {
      closeMenu();
      return;
    }
    if (_heading != null) {
      closeHeading();
      return;
    }
    if (_textMode || selecting) return; // the chrome carries text mode's and selection's controls
    _chromeVisible = !_chromeVisible;
    notifyListeners();
  }

  void showChrome() {
    if (_chromeVisible) return;
    _chromeVisible = true;
    notifyListeners();
  }

  void openMenu(int verse) {
    _menuVerse = verse;
    notifyListeners();
  }

  void closeMenu() {
    if (_menuVerse == null) return;
    _menuVerse = null;
    notifyListeners();
  }

  /// Called by the engine for each verse played through (listening progress).
  static void Function(int verse) listenRecorder(UserStore? user, Recording recording) =>
      (verse) => user?.recordVerseListened(recording.id, verse);

  @override
  void dispose() {
    _noticeTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

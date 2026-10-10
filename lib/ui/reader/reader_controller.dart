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
import '../../app/audio_library.dart';
import '../../app/app_update.dart';
import '../../app/rating.dart';
import '../../app/reminders.dart';
import '../../app/personal_data.dart';
import '../design/app_theme.dart';
import '../design/components/rubric.dart';
import '../design/tokens.g.dart';
import '../widgets/page_viewer.dart';

/// How long a notice such as «بدأ باب جديد» stays (the prototype's toast).
const Duration kNoticeDuration = Duration(seconds: 2);

class ReaderController extends ChangeNotifier {
  final AppContent content;
  final PageViewerController viewer;
  final UserStore? user;
  final SettingsStore? store;

  /// The recordings: which is chosen, which are on the device, downloads (set at boot).
  AudioLibrary? library;

  /// «التنبيهات», set at boot (none in tests unless given).
  Reminders? reminders;

  /// The rating request, told of each day audio plays (set at boot).
  RatingPrompt? rating;

  /// Google Play's update check, for the home screen's banner (Android builds).
  AppUpdate? update;

  /// Bookmarks and notes (set at boot; null in tests that do not need them). The
  /// reader redraws when they change (ribbons in text mode, the menu's icons).
  PersonalData? get personal => _personal;
  set personal(PersonalData? p) {
    _personal?.removeListener(notifyListeners);
    _personal = p;
    p?.addListener(notifyListeners);
  }

  PersonalData? _personal;

  Recording _recording;
  PlaybackEngine? _engine; // null until the recording is on the device
  StreamSubscription<EngineState>? _engineSub;

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
    required Recording recording,
    required this.viewer,
    this._engine,
    this.user,
    this.store,
    PlaybackSettings initialSettings = const PlaybackSettings(),
    int initialVerse = 1,
  })  : _verse = initialVerse,
        _recording = recording,
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
      applyThemeChoice(s.themeChoice);
      appNightInk.value = nightInkById(s.nightInk);
    }
    _attachEngine();
    _subs.add(viewer.onVerseTap.listen(tapVerse));
    _subs.add(viewer.onVerseLongPress.listen(openMenu));
    _subs.add(viewer.onPageTap.listen((_) => toggleChrome()));
    _subs.add(viewer.onPageChange.listen((_) => _onPageSwiped()));
    _subs.add(viewer.onChapterTap.listen(openHeading));
    viewer.setActiveVerse(_verse);
  }

  Recording get recording => _recording;
  PlaybackEngine? get engine => _engine;

  void _attachEngine() {
    final e = _engine;
    if (e == null) return;
    e.plan.settings = _settings;
    e.setSpeed(_speed);
    _engineSub = e.states.listen(_onEngineState);
  }

  /// Another recording (or the same one, once downloaded or deleted): the verse
  /// stays, the repeat counters start again (features-v3 reciter-catalog). The
  /// previous engine belongs to [library], which has already stopped it.
  Future<void> setAudio(Recording recording, PlaybackEngine? engine) async {
    await _engineSub?.cancel();
    _engineSub = null;
    _recording = recording;
    _engine = engine;
    _engineState = null;
    _detached = false;
    _speed = store?.speedFor(recording.id) ?? 1;
    _attachEngine();
    viewer.setActiveVerse(_verse);
    notifyListeners();
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

  /// The index of the chapter whose heading popover is open.
  int? get headingIndex => _heading;

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

  /// The matn's size in text mode, in px (ADR 0021).
  double get verseSize => kDefaultVerseSize * _textScale;
  bool get night => viewer.night;

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
    engine?.setSpeed(v);
    notifyListeners();
  }

  ThemeChoice get themeChoice => appThemeChoice.value;
  TzNightInk get nightInk => appNightInk.value;

  /// «المظهر»: paper, night, or with the system.
  void setThemeChoice(ThemeChoice c) {
    store?.themeChoice = c;
    applyThemeChoice(c);
    notifyListeners();
  }

  /// One of the two palettes, chosen outright.
  void setTheme(ReaderTheme t) => setThemeChoice(t == ReaderTheme.paper ? ThemeChoice.paper : ThemeChoice.night);

  /// «لون الحبر الليلي» (ADR 0020): stored and applied at once.
  void setNightInk(TzNightInk ink) {
    store?.nightInk = ink.id;
    appNightInk.value = ink;
    notifyListeners();
  }

  /// Text mode keeps the top bar and the player on screen: there is no page to uncover.
  void setTextMode(bool on) {
    _textMode = on;
    store?.textMode = on;
    _menuVerse = null;
    _symbol = null;
    if (on) _chromeVisible = true;
    notifyListeners();
  }

  void setTextScale(double v) {
    _textScale = nearestTextScale(v);
    store?.textScale = _textScale;
    notifyListeners();
  }

  /// The night page follows the theme (ReaderScreen); kept for the viewer's own tests.
  void setNight(bool on) {
    viewer.setNightMode(on);
    notifyListeners();
  }

  // ── transport ──
  // The section (ADR 0003) starts where play was pressed: «تكرار المقطع» returns
  // to that verse, never to a chapter's first verse the listener did not choose.
  bool _sectionSet = false; // a section was started in this session

  /// From [verse] to the end of its chapter: what ▶ plays when nothing is chosen.
  PlaybackScope _fromHere(int verse) => PlaybackScope(verse, content.matn.chapterOfVerse(verse).toVerse);

  /// The section as the player shows it: the one in hand, or the one ▶ would start.
  PlaybackScope? get section {
    final e = engine;
    if (e == null) return null;
    return _inSection(e, _verse) ? e.plan.scope : _fromHere(_verse);
  }

  bool _inSection(PlaybackEngine e, int verse) =>
      _sectionSet && e.plan.scope.fromVerse <= verse && verse <= e.plan.scope.toVerse;

  Future<void> playPause() async {
    final e = engine;
    if (e == null) return;
    if (playing) {
      await e.pause();
    } else {
      _detached = false;
      viewer.setActiveVerse(_verse);
      final state = _engineState;
      if (state != null && !state.finished && e.plan.verse == _verse) {
        await e.resume(); // in the middle of a verse: the same section, the same counters
      } else if (_inSection(e, _verse)) {
        // The section in hand: again from its start once it has ended, or from
        // the verse the listener moved to inside it.
        await e.play(state != null && state.finished && e.plan.verse == _verse ? null : _verse);
      } else {
        e.plan.scope = _fromHere(_verse);
        _sectionSet = true;
        await e.play(_verse);
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
    _sectionSet = true;
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
      // Outside the section in hand, a new one starts from the tapped verse.
      if (!_inSection(e, verse)) {
        e.plan.scope = _fromHere(verse);
        _sectionSet = true;
      }
      await e.jumpTo(verse);
    }
    notifyListeners();
  }

  // ── following playback ──
  void _onEngineState(EngineState s) {
    if (s.playing && !(_engineState?.playing ?? false)) rating?.used();
    final changed = s.verse != _verse;
    final previous = _engineState;
    _engineState = s;
    // Playback itself crossing into a new chapter (a jump sets _verse first, so never here).
    if (changed && s.playing && content.matn.chapterOfVerse(s.verse).id != chapter.id) {
      showNotice('بدأ باب جديد · ${content.matn.chapterOfVerse(s.verse).title}');
    }
    if (changed) {
      _verse = s.verse;
      if (!_detached) viewer.setActiveVerse(s.verse);
    }
    // The engine reports on every position tick. Nothing on screen reads the
    // position from here (the player listens to the audio itself), so only a
    // state that differs rebuilds the reader (item 3.13, F-60).
    if (!_sameState(previous, s)) notifyListeners();
  }

  static bool _sameState(EngineState? a, EngineState b) =>
      a != null &&
      a.verse == b.verse &&
      a.inTitle == b.inTitle &&
      a.playing == b.playing &&
      a.inGap == b.inGap &&
      a.verseRepetition == b.verseRepetition &&
      a.sectionRepetition == b.sectionRepetition &&
      a.finished == b.finished;

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

  /// Shows a short notice over the page (e.g. «حُفظ المرجع على البيت N»).
  void showNotice(String text) {
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
    _symbol = null;
    notifyListeners();
  }

  void closeMenu() {
    if (_menuVerse == null) return;
    _menuVerse = null;
    notifyListeners();
  }

  // ── the rubric ink: reader names and symbols (ADRs 0015, 0021) ──
  bool? _showRubric;
  ({int verse, Rubric mark})? _symbol;

  /// «إبراز رموز القراء وأسمائهم»: on unless the student turned it off.
  bool get showRubric => _showRubric ?? store?.showRubric ?? true;

  void setShowRubric(bool on) {
    _showRubric = on;
    store?.showRubric = on;
    if (!on) _symbol = null;
    notifyListeners();
  }

  /// The reader symbol whose tip is open, with its verse.
  ({int verse, Rubric mark})? get symbol => _symbol;

  void openSymbol(int verse, Rubric mark) {
    _menuVerse = null;
    _symbol = (verse: verse, mark: mark);
    notifyListeners();
  }

  void closeSymbol() {
    if (_symbol == null) return;
    _symbol = null;
    notifyListeners();
  }

  // ── the commentary sheet (item 3.9, ADR 0022): tied to one verse ──
  int? _commentaryVerse;
  String? _commentaryBook;

  /// The verse whose explanation is open in the sheet, if any.
  int? get commentaryVerse => _commentaryVerse;

  /// The book last read (ADR 0018).
  String? get commentaryBook => _commentaryBook ?? store?.commentaryBook;

  /// «الشرح»: opens the sheet on [verse], or moves it there.
  void openCommentary(int verse) {
    _menuVerse = null;
    _symbol = null;
    closeHeading();
    _commentaryVerse = verse;
    _chromeVisible = true;
    // On the page, the verse's page is shown.
    final page = content.layout.pageOfVerse(verse);
    if (!_textMode && page != viewer.currentPage) viewer.setPage(page, false);
    notifyListeners();
  }

  void closeCommentary() {
    if (_commentaryVerse == null) return;
    _commentaryVerse = null;
    notifyListeners();
  }

  void setCommentaryBook(String id) {
    _commentaryBook = id;
    store?.commentaryBook = id;
  }

  // ── the tablet split: page and commentary side by side (plan P8, commentary-split-screen) ──
  bool _splitOpen = false;
  bool _splitFollow = true;
  int _splitPinned = 1;

  bool get splitOpen => _splitOpen;

  /// «يتبع التلاوة»: the panel explains the reader's verse (playing or selected).
  bool get splitFollow => _splitFollow;

  /// The verse the panel explains.
  int get splitVerse => _splitFollow ? _verse : _splitPinned;

  /// Opens the panel on [verse]. Another verse than the reader's pins the panel there
  /// (following would move it away at once); the switch brings following back.
  void openSplit(int verse) {
    _splitOpen = true;
    _splitPinned = verse;
    if (verse != _verse) _splitFollow = false;
    notifyListeners();
  }

  void closeSplit() {
    if (!_splitOpen) return;
    _splitOpen = false;
    notifyListeners();
  }

  /// Turning following off keeps the panel where it is (on the reader's verse).
  void setSplitFollow(bool on) {
    if (!on && _splitFollow) _splitPinned = _verse;
    _splitFollow = on;
    notifyListeners();
  }

  /// The student moved in the panel (a tab, previous / next) to [verse]: it stays there.
  void pinSplit(int verse) {
    _splitPinned = verse;
    if (!_splitFollow) return notifyListeners();
    _splitFollow = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _engineSub?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

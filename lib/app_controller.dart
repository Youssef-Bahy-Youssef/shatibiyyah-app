// lib/app_controller.dart — orchestrator. Port of js/app.js main(): boots the modules,
// wires AudioEngine / PageViewer / Sync events into observable state, and owns the layout
// chrome state (bar state machine, resume/session chips, immersive auto-hide, per-chapter
// progress, unified search).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'data/app_content.dart';
import 'data/recording_repository.dart';
import 'models/playback_settings.dart';
import 'services/audio_service.dart';
import 'services/data_service.dart';
import 'services/preferences_service.dart';
import 'services/sync_service.dart';
import 'services/verse_text.dart';
import 'ui/widgets/page_viewer.dart';
import 'utils/arabic.dart';

enum SheetType { pause, speed, verse, section }

class SavedSession {
  final int verseId;
  final int chapterId;
  final String chapterName;
  final String verseFirst8;
  final int pageNum;
  const SavedSession(
    this.verseId,
    this.chapterId,
    this.chapterName,
    this.verseFirst8,
    this.pageNum,
  );
}

class SearchResults {
  final List<IndexEntry> verses;
  final List<int> chapters; // chapter indices
  final String normQuery;
  const SearchResults(this.verses, this.chapters, this.normQuery);
  bool get isEmpty => verses.isEmpty && chapters.isEmpty;
}

class AppController extends ChangeNotifier {
  final ShatibiyyahData data;
  final VerseTextData verseText;
  final AudioEngine audio;
  final PageViewerController viewer;
  final SyncController sync;
  final Prefs prefs;

  // high-frequency time stream (scrubber + times) — isolated from notifyListeners()
  final ValueNotifier<TimeUpdate> time = ValueNotifier(
    const TimeUpdate(0, 0, 0),
  );

  // ── bottom-bar state machine (idle / playing / paused) ──
  String barState = 'idle';

  // ── chrome / sheets ──
  bool consoleExpanded = false; // .controls-panel.expanded
  bool settingsOpen = false;
  bool rangeSheetOpen = false;
  bool searchOverlayOpen = false;
  bool pickerOpen = false;
  SheetType pickerType = SheetType.pause;

  // ── clickable chapter headers ──
  int? selectedChapter; // chapterAction band

  // ── resume / detach chip ──
  bool detached = false;
  int resumeVerse = 1;

  // ── session chip ──
  bool sessionChipVisible = false;
  SavedSession? _savedSession;
  bool _hasPlayed = false;
  Timer? _saveSessionTimer;

  // ── per-chapter progress ──
  late Map<int, double> chapterProgress;
  Timer? _saveProgTimer;

  // ── immersive ──
  bool wide = false; // ≥1025px (set each build)
  bool controlsHidden = false;
  bool keepControlsVisible = false;
  Timer? _autoHideTimer;
  bool _controlInteractionOccurred = false;

  final List<StreamSubscription> _subs = [];

  bool _booted = false;

  /// The bundled content (repositories) and the recording the reader plays.
  final AppContent content;
  final Recording recording;

  /// The recording's file on this device, or null while it is not downloaded.
  final String? audioFilePath;

  AppController({
    required this.content,
    required this.recording,
    required this.audioFilePath,
    required this.data,
    required this.verseText,
    required this.audio,
    required this.viewer,
    required this.sync,
    required this.prefs,
  }) {
    chapterProgress = _loadChapProgress();
    keepControlsVisible = prefs.getLS(K.keepControls, '0') == '1';
    _wire();
  }

  bool get isImmersive => !wide;

  /// False until the recording is on the device; the transport is inert meanwhile.
  bool get audioAvailable => audio.available;
  bool get isPaused => audio.isPaused;
  int get currentVerse => audio.currentVerse;
  String get chapterName => audio.getChapterName();
  bool get night => viewer.night;
  int get brightnessPct => viewer.brightnessPct;

  // ── wiring (ported from app.js engine events → DOM) ──
  void _wire() {
    _subs.add(audio.onVerseChange.listen(_onVerseChange));
    _subs.add(audio.onTimeUpdate.listen(_onTimeUpdate));
    _subs.add(audio.onRangeChange.listen((_) => refreshAll()));
    _subs.add(audio.onReady.listen((_) => refreshAll()));
    _subs.add(
      audio.onPlay.listen((_) {
        _hasPlayed = true;
        _hideSessionChip();
        setBarState('playing');
        _scheduleAutoHide();
        notifyListeners();
      }),
    );
    _subs.add(
      audio.onPause.listen((_) {
        _persistSession();
        setBarState(_barStateFromAudio());
        _scheduleAutoHide();
        notifyListeners();
      }),
    );
    _subs.add(
      audio.onEnded.listen((_) {
        setBarState('idle');
      }),
    );

    _subs.add(
      viewer.onChapterTap.listen(
        (idx) => selectChapterHeader(idx, navigate: false),
      ),
    );
    _subs.add(viewer.onVerseTap.listen((_) => clearChapterSelection()));
    _subs.add(viewer.onPageTap.listen((_) => _onPageTap()));
    _subs.add(viewer.onOpenSearch.listen((_) => openSearchOverlay()));
    _subs.add(viewer.onViewPref.listen((_) => notifyListeners()));

    _subs.add(
      sync.onDetachChange.listen((d) {
        detached = d.detached;
        if (d.detached && d.verse != null) resumeVerse = d.verse!;
        notifyListeners();
      }),
    );
  }

  // ported from app.js: onVerseChange(d)
  void _onVerseChange(VerseChange d) {
    _trackChapterProgress(d.verse);
    _scheduleSessionSave();
    notifyListeners();
  }

  // ported from app.js: onTimeUpdate(d)
  void _onTimeUpdate(TimeUpdate d) {
    time.value = d;
  }

  // ported from app.js: refreshAll()
  void refreshAll() => notifyListeners();

  // ── bottom-bar state machine (ported) ──
  String _barStateFromAudio() {
    if (!audio.isPaused) return 'playing';
    final pos = audio.audio.position.inMilliseconds / 1000.0;
    final at = (pos - audio.rangeStartTime).abs() < 0.4;
    return at ? 'idle' : 'paused';
  }

  void setBarState(String s) {
    barState = s;
    notifyListeners();
  }

  // ── transport ──
  void togglePlay() => audio.togglePlay();
  void prev() => audio.prev();
  void next() => audio.next();
  void doStop() {
    audio.stop();
    setBarState('idle');
  }

  // ── range status card (ported: updateRangeStatusCard) ──
  ({String icon, String title, String sub}) rangeStatus() {
    if (audio.mode == 'chapter') {
      final c =
          data.chapters[clampNum(
            audio.chapterIdx,
            0,
            data.chapters.length - 1,
          ).toInt()];
      return (
        icon: '📖',
        title: c.name,
        sub: 'الأبيات ${ar(c.startVerse)}–${ar(c.endVerse)}',
      );
    } else if (audio.mode == 'range') {
      return (
        icon: '🎯',
        title: 'نطاق مخصص',
        sub: 'الأبيات ${ar(audio.fromVerse)}–${ar(audio.toVerse)}',
      );
    }
    return (
      icon: '📚',
      title: 'كل المتن',
      sub: 'من البيت ${ar(1)} إلى ${ar(data.lastVerse)}',
    );
  }

  // ── tabs / mode ──
  void setMode(String m) => audio.setMode(m);

  // ── chapter list ──
  // ported from app.js: selectChapter(i)
  void selectChapter(int i) {
    audio.setChapter(i);
    sync.reattach();
    closeRangeSheet();
  }

  // ── clickable chapter headers (ported) ──
  void selectChapterHeader(int idx, {bool navigate = false}) {
    if (idx < 0 || idx >= data.chapters.length) return;
    selectedChapter = idx;
    viewer.setSelectedChapter(idx, navigate: navigate);
    if (isImmersive) showControls();
    notifyListeners();
  }

  void clearChapterSelection() {
    if (selectedChapter == null) return;
    selectedChapter = null;
    viewer.setSelectedChapter(null);
    notifyListeners();
  }

  // ported from app.js: playSelectedChapter()
  void playSelectedChapter() {
    final idx = selectedChapter;
    if (idx == null) return;
    final c = data.chapters[idx];
    if (c.startTime == null || !(c.startTime! > 0)) return;
    sync.playChapter(idx);
    clearChapterSelection();
    notifyListeners();
  }

  ({String name, String meta, bool canPlay})? chapterActionInfo() {
    final idx = selectedChapter;
    if (idx == null) return null;
    final c = data.chapters[idx];
    final hasTime = c.startTime != null && c.startTime! > 0;
    return (
      name: c.name,
      meta:
          '${ar(c.verseCount)} بيت · الأبيات ${ar(c.startVerse)}–${ar(c.endVerse)}',
      canPlay: hasTime,
    );
  }

  // ── range inputs ──
  void commitRange(int f, int t) => audio.setRange(f, t);
  void stepRange(String which, int dir) {
    if (which == 'from') {
      audio.setRange(audio.fromVerse + dir, audio.toVerse);
    } else {
      audio.setRange(audio.fromVerse, audio.toVerse + dir);
    }
  }

  // ── picker sheets ──
  void openPicker(SheetType t) {
    pickerType = t;
    pickerOpen = true;
    notifyListeners();
  }

  void closePicker() {
    pickerOpen = false;
    notifyListeners();
  }

  List<num> pickerOptions() {
    switch (pickerType) {
      case SheetType.pause:
        return kPauseOpts;
      case SheetType.speed:
        return kSpeedOpts;
      case SheetType.verse:
      case SheetType.section:
        return kRepOpts;
    }
  }

  num pickerCurrent() {
    switch (pickerType) {
      case SheetType.pause:
        return audio.pauseSeconds;
      case SheetType.speed:
        return audio.speed;
      case SheetType.verse:
        return audio.verseRepsTotal;
      case SheetType.section:
        return audio.sectionRepsTotal;
    }
  }

  void pickerSet(num v) {
    switch (pickerType) {
      case SheetType.pause:
        audio.setPause(v.toInt());
        break;
      case SheetType.speed:
        audio.setSpeed(v.toDouble());
        break;
      case SheetType.verse:
        audio.setVerseReps(v.toDouble());
        break;
      case SheetType.section:
        audio.setSectionReps(v.toDouble());
        break;
    }
    notifyListeners();
  }

  String pickerTitle() {
    switch (pickerType) {
      case SheetType.pause:
        return '⏱ فاصل زمني';
      case SheetType.speed:
        return '🎚 سرعة التلاوة';
      case SheetType.verse:
        return '🔁 تكرار البيت';
      case SheetType.section:
        return '🔁 تكرار المقطع';
    }
  }

  // control-card value labels (ported: updateCardLabels)
  String get valPause =>
      audio.pauseSeconds == 0 ? 'بدون' : '${ar(audio.pauseSeconds)} ث';
  String get valSpeed => '${ar(audio.speed)}×';
  String get valVerse =>
      audio.verseRepsTotal == double.infinity ? '∞' : ar(audio.verseRepsTotal);
  String get valSection => audio.sectionRepsTotal == double.infinity
      ? '∞'
      : ar(audio.sectionRepsTotal);

  // ── console / panels / sheets open-close ──
  void openConsole() {
    consoleExpanded = true;
    notifyListeners();
  }

  void closeConsole() {
    consoleExpanded = false;
    _scheduleAutoHide();
    notifyListeners();
  }

  void toggleConsole() => consoleExpanded ? closeConsole() : openConsole();

  void openSettings() {
    settingsOpen = true;
    notifyListeners();
  }

  void closeSettings() {
    settingsOpen = false;
    notifyListeners();
  }

  void openRangeSheet() {
    rangeSheetOpen = true;
    notifyListeners();
  }

  void closeRangeSheet() {
    rangeSheetOpen = false;
    _scheduleAutoHide();
    notifyListeners();
  }

  void openSearchOverlay() {
    searchOverlayOpen = true;
    notifyListeners();
  }

  void closeSearchOverlay() {
    searchOverlayOpen = false;
    _scheduleAutoHide();
    notifyListeners();
  }

  // ── settings: night / brightness ──
  void toggleNight() => viewer.setNightMode(!viewer.night);
  void setBrightness(int v) => viewer.setBrightness(v);

  // ── resume / detach ──
  void reattach() => sync.reattach();

  // ── session chip (ported from app.js Feature 1) ──
  String _firstWords(String s, int n) {
    final w = s.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    return w.take(n).join(' ') + (w.length > n ? '…' : '');
  }

  void _persistSession() {
    if (!_hasPlayed) return;
    final v = audio.currentVerse;
    final idx = data.chapterIndexForVerse(v);
    final vt = verseText.byId[v];
    final obj = {
      'verseId': v,
      'chapterId': idx,
      'chapterName': (idx >= 0 ? data.chapters[idx].name : '').isNotEmpty
          ? data.chapters[idx].name
          : audio.getChapterName(),
      'verseFirst8': vt != null ? _firstWords(vt.sadr, 8) : '',
      'pageNum': data.pageOfVerse(v) ?? 1,
    };
    prefs.setString(K.session, json.encode(obj));
  }

  void _scheduleSessionSave() {
    _saveSessionTimer?.cancel();
    _saveSessionTimer = Timer(
      const Duration(milliseconds: 2000),
      _persistSession,
    );
  }

  void initSessionChip() {
    final raw = prefs.getString(K.session);
    if (raw == null) return;
    Map<String, dynamic> saved;
    try {
      saved = json.decode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final verseId = saved['verseId'] as int?;
    if (verseId == null) return;
    final idx = data.chapterIndexForVerse(verseId);
    final chap = (saved['chapterName'] as String?)?.isNotEmpty == true
        ? saved['chapterName'] as String
        : (idx >= 0 ? data.chapters[idx].name : '');
    final text =
        (saved['verseFirst8'] as String?) ??
        (verseText.byId[verseId] != null
            ? _firstWords(verseText.byId[verseId]!.sadr, 8)
            : '');
    _savedSession = SavedSession(
      verseId,
      idx,
      chap,
      text,
      (saved['pageNum'] as int?) ?? 1,
    );
    sessionChipVisible = true;
    notifyListeners();
  }

  SavedSession? get savedSession => _savedSession;

  void resumeFromChip() {
    final s = _savedSession;
    if (s == null) return;
    _hasPlayed = true;
    sync.jumpToVerse(s.verseId, play: true);
    _hideSessionChip();
  }

  void _hideSessionChip() {
    if (!sessionChipVisible) return;
    sessionChipVisible = false;
    notifyListeners();
  }

  void dismissSessionChip() => _hideSessionChip();

  // ── per-chapter progress (ported from app.js) ──
  Map<int, double> _loadChapProgress() {
    final raw = prefs.getString(K.chapProg);
    if (raw == null) return {};
    try {
      final m = json.decode(raw) as Map<String, dynamic>;
      return {
        for (final e in m.entries)
          int.parse(e.key): (e.value as num).toDouble(),
      };
    } catch (_) {
      return {};
    }
  }

  void _scheduleSaveProgress() {
    _saveProgTimer?.cancel();
    _saveProgTimer = Timer(const Duration(milliseconds: 800), () {
      prefs.setString(
        K.chapProg,
        json.encode({
          for (final e in chapterProgress.entries) e.key.toString(): e.value,
        }),
      );
    });
  }

  void _trackChapterProgress(int v) {
    final i = audio.mode == 'chapter'
        ? audio.chapterIdx
        : data.chapterIndexForVerse(v);
    if (i < 0) return;
    final c = data.chapters[i];
    final span = (c.endVerse - c.startVerse).clamp(1, 1 << 30);
    double f = clampNum((v - c.startVerse) / span, 0, 1).toDouble();
    if (v >= c.endVerse) f = 1;
    if (f > (chapterProgress[i] ?? 0)) {
      chapterProgress[i] = f;
      _scheduleSaveProgress();
      notifyListeners();
    }
  }

  // ── immersive (ported from app.js) ──
  void _onPageTap() {
    if (selectedChapter != null) {
      clearChapterSelection();
      return;
    }
    if (!isImmersive) return;
    if (controlsHidden) {
      showControls();
    } else {
      hideControls();
    }
  }

  int _getHideDelay() {
    if (_controlInteractionOccurred) return 5000;
    final pos = audio.audio.position.inMilliseconds / 1000.0;
    if (!audio.isPaused) return 3000;
    if (pos > 0) return 9000;
    return 3000;
  }

  bool _anyPanelOpen() =>
      consoleExpanded ||
      rangeSheetOpen ||
      searchOverlayOpen ||
      selectedChapter != null;

  void _scheduleAutoHide() {
    _autoHideTimer?.cancel();
    if (keepControlsVisible || !isImmersive) return;
    if (controlsHidden) return;
    _autoHideTimer = Timer(
      Duration(milliseconds: _getHideDelay()),
      hideControls,
    );
  }

  void showControls() {
    _controlInteractionOccurred = false;
    controlsHidden = false;
    notifyListeners();
    _scheduleAutoHide();
  }

  void hideControls() {
    if (keepControlsVisible) {
      _autoHideTimer?.cancel();
      return;
    }
    if (_anyPanelOpen()) {
      _scheduleAutoHide();
      return;
    }
    _autoHideTimer?.cancel();
    _controlInteractionOccurred = false;
    controlsHidden = true;
    notifyListeners();
  }

  void noteControlInteraction() {
    _controlInteractionOccurred = true;
    _scheduleAutoHide();
  }

  void setKeepControls(bool v) {
    keepControlsVisible = v;
    prefs.setLS(K.keepControls, v ? '1' : '0');
    if (v) {
      _autoHideTimer?.cancel();
      controlsHidden = false;
    } else {
      _scheduleAutoHide();
    }
    notifyListeners();
  }

  /// Called once after the first frame to set the immersive initial state.
  void initImmersive(bool wide) {
    this.wide = wide;
    if (isImmersive && !keepControlsVisible) controlsHidden = true;
    notifyListeners();
  }

  // ── unified search (ported from app.js: runSearchOn) ──
  SearchResults runSearch(String q) {
    final nq = normalize(q);
    if (q.trim().length < 2 || nq.isEmpty) {
      return SearchResults(const [], const [], nq);
    }
    final chapHits = <int>[];
    for (int i = 0; i < data.chapters.length; i++) {
      if (normalize(data.chapters[i].name).contains(nq)) chapHits.add(i);
    }
    chapHits.sort(
      (a, b) =>
          data.chapters[a].startVerse.compareTo(data.chapters[b].startVerse),
    );
    final verseHits = <IndexEntry>[];
    for (final v in verseText.index) {
      if (v.norm.contains(nq)) {
        verseHits.add(v);
        if (verseHits.length >= 30) break;
      }
    }
    return SearchResults(verseHits, chapHits, nq);
  }

  void searchPickVerse(int id) {
    sync.jumpToVerse(id, play: false);
  }

  void searchPickChapter(int idx) {
    selectChapterHeader(idx, navigate: true);
  }

  // ── boot (ported from app.js: bottom of main()) ──
  Future<void> boot() async {
    if (_booted) return; // guard: HomeScreen.initState may fire more than once
    _booted = true;
    await audio.initSource(
      filePath: audioFilePath,
      recordingId: recording.id,
      artist: recording.reciterName,
    );
    audio.setMode(audio.mode);
    viewer.setActiveVerse(audio.currentVerse);
    setBarState('idle');
    initSessionChip();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _autoHideTimer?.cancel();
    _saveSessionTimer?.cancel();
    _saveProgTimer?.cancel();
    time.dispose();
    super.dispose();
  }
}

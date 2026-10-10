// lib/ui/widgets/page_viewer.dart — PageViewer: renders a scanned page + a highlight
// overlay with a transform-based pinch-zoom / pan engine. 100% port of js/page-viewer.js.
//
// COORDINATE MODEL (verbatim from the JS): every box in verses.json is native image
// pixel space; every page is 1130×1735. baseScale = displayedWidth/1130 maps image→base;
// view {zoom,tx,ty} is a transform on the stage (image + overlay): screen = base·zoom+(tx,ty).
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show HapticFeedback;

import '../../models/playback_settings.dart' show K, clampd;
import '../../services/data_service.dart';
import '../../services/preferences_service.dart';
import '../design/dashed.dart';
import '../design/night_page.dart';
import '../design/tokens.g.dart';

const double _pageW = 1130;
const double _pageH = 1735;
/// The playing wash glides to the next verse in this long (v2.css .hl.play, emphasized).
const int _glideMs = 320;
const int _pulseMs = 460;
const double _minZoom = 1;
const double _maxZoom = 4;
const double _tapSlop = 10;
const double _swipeMin = 55;
const int _dblMs = 300;
const double _dblSlop = 34;


/// Hold time before a verse's action menu opens (features-v3: 450 ms).
const int kLongPressMs = 450;

// page-viewer.js COLORS / CHAPTER_COLORS
class _Col {
  final Color fill, stroke, ghost;
  const _Col(this.fill, this.stroke, this.ghost);
}

/// The page's own marks follow the page, not the app theme: the paper tokens on the
/// printed page, the night tokens on the night page.
TzColors _pageTokens(bool night) => night ? TzColors.night : TzColors.paper;

/// The playing verse's colours: the gilt wash, gilt, and the softer wash (ghost boxes).
_Col _playingCol(bool night) {
  final k = _pageTokens(night);
  return _Col(k.giltWash, k.gilt, k.giltWashSoft);
}

class ViewPrefs {
  final bool night;
  final bool showBoxes;
  const ViewPrefs(this.night, this.showBoxes);
}

/// PageViewerController — owns all page/transform/highlight state and the gesture engine.
/// Mirrors the PageViewer class from page-viewer.js. Emits user interactions via streams.
class PageViewerController extends ChangeNotifier {
  final ShatibiyyahData data;
  final Prefs prefs;

  // layout / fit
  double baseW = 0, baseH = 0, baseScale = 1, viewW = 0, viewH = 0;

  // view transform (single source of truth) — displayed values used by the painter.
  double zoom = 1, tx = 0, ty = 0;

  // page + highlight state
  int currentPage = 0;
  int? activeId;
  Rect? activeBox;
  Rect? prevBox;
  double hiliteStart = 0;
  ({Rect box, double start})? pulse;

  /// A run of selected verses (features-v3 multi-verse-selection), drawn dashed.
  ({int from, int to})? selection;

  /// Bookmark ribbons: verse → the bookmark colour's index in the tokens' list.
  Map<int, int> ribbons = const {};

  // chapter-header overlay
  int? chapterSel;
  int? chapterHover;

  // view prefs (persisted)
  late bool night;

  /// Whether the playing wash is drawn: only with a recitation loaded, and not
  /// under a popover's spotlight (handoff specs: reader-none has no wash, verse
  /// and heading show the spotlight alone).
  bool showPlaying = true;

  /// The ink the night page is drawn in (ADR 0020); item 3.6 sets the reader's choice.
  TzNightInk nightInk = TzNightPage.jade;
  late bool showBoxes;

  bool reduceMotion = false;

  // ── event streams (mirror addEventListener) ──
  final _verseTap = StreamController<int>.broadcast();
  final _verseLongPress = StreamController<int>.broadcast();
  final _pageChange = StreamController<int>.broadcast();
  final _chapterTap = StreamController<int>.broadcast();
  final _pageTap = StreamController<void>.broadcast();
  final _viewPref = StreamController<ViewPrefs>.broadcast();
  final _openSearch = StreamController<void>.broadcast();
  Stream<int> get onVerseTap => _verseTap.stream;

  /// A verse held for [kLongPressMs] without moving: opens its action menu.
  Stream<int> get onVerseLongPress => _verseLongPress.stream;
  Stream<int> get onPageChange => _pageChange.stream;
  Stream<int> get onChapterTap => _chapterTap.stream;
  Stream<void> get onPageTap => _pageTap.stream;
  Stream<ViewPrefs> get onViewPref => _viewPref.stream;
  Stream<void> get onOpenSearch => _openSearch.stream;

  // tickers / clock
  TickerProvider? _vsync;
  final Stopwatch _clock = Stopwatch()..start();
  AnimationController? _xform; // transform animation
  Ticker? _overlay; // highlight repaint
  final _Repaint _repaint = _Repaint();

  /// Fires when the highlight layer must be painted again (a new verse, a frame
  /// of its glide, a ribbon, a selection): nothing is rebuilt for it.
  Listenable get repaint => _repaint;
  Ticker? _momentum;
  double _zoom0 = 1, _tx0 = 0, _ty0 = 0, _zoomT = 1, _txT = 0, _tyT = 0;

  PageViewerController(this.data, this.prefs) {
    night = prefs.getLS(K.night, '0') == '1';
    showBoxes = prefs.getLS(K.boxes, '0') == '1';
  }

  void attach(TickerProvider vsync) {
    _vsync = vsync;
    _xform = AnimationController(vsync: vsync)..addListener(_onXformTick);
    // A frame of the highlight's glide is a repaint of its layer, not a rebuild.
    _overlay = vsync.createTicker((elapsed) {
      final at = elapsed.inMicroseconds / 1000.0;
      _animMs += at - _tickerAt;
      _tickerAt = at;
      _repaint.now();
      if (!_needsAnim(_animNow())) {
        _overlay?.stop();
        _clearFinished();
      }
    });
  }

  /// Releases the tickers created from the widget's TickerProvider. The controller
  /// outlives the widget (the app owns it); while detached, view changes apply at
  /// once instead of animating (see _setView).
  void detach() {
    _xform?.dispose();
    _overlay?.dispose();
    _momentum?.dispose();
    _xform = null;
    _overlay = null;
    _momentum = null;
    _vsync = null;
  }

  double _now() => _clock.elapsedMilliseconds.toDouble();

  // The highlight's glide and the pulse run on frame time: this clock moves only
  // with the frames of their ticker, so they last their length in frames shown
  // (and in tests), whatever the wall clock does.
  double _animMs = 0, _tickerAt = 0;
  double _animNow() => _animMs;

  void _emit(StreamController c) => c.add(null);

  // ── layout / fit (ported: _relayout) ──
  void relayout(double w, double h) {
    if (w <= 0) return;
    if (w == viewW && h == viewH) return;
    viewW = w;
    viewH = h;
    baseW = w;
    baseH = (_pageH * (w / _pageW)).roundToDouble();
    baseScale = baseW / _pageW;
    // re-clamp / re-center after the frame (avoid notify-during-build)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (zoom > 1.02 && activeBox != null) {
        _centerOnBox(activeBox!, animate: false);
      } else {
        _setView(zoom, tx, ty, false);
      }
    });
  }

  // ── view transform (ported: _clampPan / _setView / _centerOnBox / _boxComfortable) ──
  ({double tx, double ty}) _clampPan(double zoom, double tx, double ty) {
    final sw = baseW * zoom, sh = baseH * zoom;
    if (sw <= viewW + 0.5) {
      tx = (viewW - sw) / 2;
    } else {
      tx = clampd(tx, viewW - sw, 0);
    }
    if (sh <= viewH + 0.5) {
      ty = (viewH - sh) / 2;
    } else {
      ty = clampd(ty, viewH - sh, 0);
    }
    return (tx: tx, ty: ty);
  }

  void _setView(double z, double nx, double ny, bool animate, {int dur = 300}) {
    z = clampd(z, _minZoom, _maxZoom);
    final c = _clampPan(z, nx, ny);
    if (!animate || reduceMotion || _vsync == null) {
      _xform?.stop();
      zoom = z;
      tx = c.tx;
      ty = c.ty;
      notifyListeners();
      return;
    }
    _zoom0 = zoom;
    _tx0 = tx;
    _ty0 = ty;
    _zoomT = z;
    _txT = c.tx;
    _tyT = c.ty;
    _xform!
      ..stop()
      ..duration = Duration(milliseconds: dur)
      ..reset();
    _xform!.forward();
  }

  void _onXformTick() {
    final t = const Cubic(.22, .61, .36, 1).transform(_xform!.value);
    zoom = _zoom0 + (_zoomT - _zoom0) * t;
    tx = _tx0 + (_txT - _tx0) * t;
    ty = _ty0 + (_tyT - _ty0) * t;
    notifyListeners();
  }

  void _centerOnBox(
    Rect box, {
    double? zoom,
    bool animate = true,
    bool respectVisible = false,
    int dur = 300,
  }) {
    final z = zoom ?? this.zoom;
    if (respectVisible &&
        (z - this.zoom).abs() < 0.01 &&
        _boxComfortable(box)) {
      return;
    }
    final s = baseScale;
    final cx = (box.left + box.width / 2) * s;
    final cy = (box.top + box.height / 2) * s;
    final nx = viewW / 2 - cx * z;
    final ny = viewH / 2 - cy * z;
    _setView(z, nx, ny, animate, dur: dur);
  }

  bool _boxComfortable(Rect box) {
    final s = baseScale * zoom;
    final top = box.top * s + ty;
    final bot = (box.top + box.height) * s + ty;
    final my = viewH * 0.2;
    return top >= my && bot <= viewH - my;
  }

  void resetView(bool animate) => _setView(1, 0, 0, animate);

  void setZoom(double z, bool animate) {
    if (activeBox != null && z > 1.02) {
      _centerOnBox(activeBox!, zoom: z, animate: animate);
    } else {
      _setView(z, tx, ty, animate);
    }
  }

  // ported: toggleZoom() — desktop only (≤1024px disabled). isWide passed from the view.
  void toggleZoom(bool isWide) {
    if (!isWide) return;
    if (zoom > 1.05) {
      resetView(true);
    } else if (activeBox != null) {
      _centerOnBox(activeBox!, zoom: 2.2, animate: true);
    } else {
      _setView(2.2, viewW / 2 - viewW, ty, true);
    }
  }

  // ── page rendering (ported: _loadPage / setPage / _userGo) ──
  void _loadPage(int n) {
    currentPage = n;
    notifyListeners();
  }

  void setPage(int n, bool fromUser) {
    n = clampd(n.toDouble(), 1, data.pageCount.toDouble()).toInt();
    if (n == currentPage && currentPage != 0) {
      if (fromUser) _pageChange.add(n);
      return;
    }
    _loadPage(n);
    if (activeId != null && data.pageOfVerse(activeId!) != n) {
      activeBox = null;
      prevBox = null;
    }
    if (fromUser) {
      resetView(true);
      _pageChange.add(n);
    }
    _invalidate();
  }

  void _userGo(int n) {
    n = clampd(n.toDouble(), 1, data.pageCount.toDouble()).toInt();
    if (n == currentPage) return;
    setPage(n, true);
  }

  // ── active verse highlight + follow (ported: setActiveVerse) ──
  void setActiveVerse(int id) {
    final box = data.getBox(id);
    if (box == null) return;
    final pageChanged = box.page != currentPage;
    activeId = id;
    prevBox = reduceMotion ? null : activeBox;
    activeBox = Rect.fromLTWH(box.x, box.y, box.w, box.h);
    hiliteStart = _animNow();

    if (pageChanged) {
      // v3: a page turn shows the whole new page; the view only zooms by the
      // student's own pinch or double-tap (the old 1.5× "cinematic turn" is gone).
      _loadPage(box.page);
      resetView(false);
    } else {
      _followActive(activeBox!);
    }
    _invalidate();
  }

  // ported: pulseVerse(id)
  void pulseVerse(int id) {
    final b = data.getBox(id);
    if (b == null) return;
    if (b.page != currentPage) setActiveVerse(id);
    if (reduceMotion) return;
    pulse = (box: Rect.fromLTWH(b.x, b.y, b.w, b.h), start: _animNow());
    _invalidate();
  }

  void setRibbons(Map<int, int> marks) {
    ribbons = marks;
    _invalidate();
  }

  void setSelection(({int from, int to})? range) {
    if (range == selection) return;
    selection = range;
    _invalidate();
  }

  // ported: setSelectedChapter(idx, {navigate})
  void setSelectedChapter(int? idx, {bool navigate = false}) {
    chapterSel = idx;
    if (idx != null && navigate) {
      final page = data.pageOfChapter(idx);
      final startVerse = (idx < data.chapters.length)
          ? data.chapters[idx].startVerse
          : null;
      if (page != null && page != currentPage) setPage(page, false);
      final cb = data.chapterBox(idx);
      if (cb != null) {
        _centerOnBox(cb, zoom: zoom, animate: true, respectVisible: true);
      }
      if (startVerse != null) pulseVerse(startVerse);
    }
    _invalidate();
  }

  // ported: _followActive(box)
  void _followActive(Rect box) {
    if (zoom > 1.05) {
      _centerOnBox(box, animate: true, respectVisible: true);
    } else if (baseH * zoom > viewH + 1) {
      _centerOnBox(box, zoom: zoom, animate: true, respectVisible: true);
    }
  }

  // ── overlay invalidation (ported: _invalidate / _needsAnim) ──
  void _invalidate() {
    _repaint.now();
    notifyListeners();
    if (_needsAnim(_animNow())) {
      if (!(_overlay?.isActive ?? false)) {
        _tickerAt = 0;
        _overlay?.start();
      }
    } else {
      _clearFinished();
    }
  }

  // Finished transient boxes go: the glide's start, a pulse.
  void _clearFinished() {
    final now = _animNow();
    if (prevBox != null && now - hiliteStart >= _glideMs) prevBox = null;
    if (pulse != null && now - pulse!.start >= _pulseMs) pulse = null;
  }

  bool _needsAnim(double now) {
    final cross = prevBox != null && now - hiliteStart < _glideMs;
    final pulsing = pulse != null && now - pulse!.start < _pulseMs;
    return cross || pulsing;
  }

  // ── night mode / boxes (ported) ──
  void setNightMode(bool on, {bool persist = true}) {
    night = on;
    if (persist) prefs.setLS(K.night, night ? '1' : '0');
    notifyListeners();
    _emitPref();
  }

  void setShowBoxes(bool on, {bool persist = true}) {
    showBoxes = on;
    if (persist) prefs.setLS(K.boxes, showBoxes ? '1' : '0');
    notifyListeners();
    _emitPref();
  }

  void _emitPref() => _viewPref.add(ViewPrefs(night, showBoxes));

  ViewPrefs getViewPrefs() => ViewPrefs(night, showBoxes);

  void emitOpenSearch() => _emit(_openSearch);

  /// Where verse [id] is drawn, in the viewer's local coordinates, or null when it
  /// is not on the page being shown.
  Rect? viewRectOfVerse(int id) {
    final b = data.getBox(id);
    if (b == null || b.page != currentPage) return null;
    final eff = baseScale * zoom;
    return Rect.fromLTWH(b.x * eff + tx, b.y * eff + ty, b.w * eff, b.h * eff);
  }

  /// The ribbon of verse [id] at scale [s] (page pixels × s), if it has a box here.
  Rect? ribbonBox(int id, double s) {
    final b = data.getBox(id);
    if (b == null || b.page != currentPage) return null;
    return Rect.fromLTWH((b.x + b.w) * s - 10, b.y * s - 3, 8, 18);
  }

  /// Where verse [id]'s ribbon is drawn on screen (unzoomed: the ribbon keeps its size).
  Rect? ribbonRect(int id) => ribbonBox(id, baseScale)?.shift(Offset(tx, ty));

  /// Where chapter [idx]'s printed heading is drawn on screen, if on this page.
  Rect? viewRectOfChapter(int idx) {
    final b = data.chapterBox(idx);
    if (b == null || !data.chaptersOnPage(currentPage).contains(idx)) return null;
    final eff = baseScale * zoom;
    return Rect.fromLTWH(b.left * eff + tx, b.top * eff + ty, b.width * eff, b.height * eff);
  }

  /// Where the playing wash is at [now] (the viewer's clock): gliding from the
  /// previous verse's box to the current one in 320 ms, emphasized (v2.css
  /// .hl.play); at once under reduced motion. In image pixels.
  Rect? playingRectAt(double now) {
    final to = activeBox;
    if (to == null) return null;
    final from = prevBox;
    if (from == null) return to;
    final t = clampd((now - hiliteStart) / _glideMs, 0, 1);
    return Rect.lerp(from, to, TzMotion.emphasized.transform(t))!;
  }

  /// The night page's colour matrix in [ink] (design/night_page.dart).
  static List<double> nightPageMatrix(TzNightInk ink) => nightInkMatrix(ink);

  // ── hit-testing (ported: _imageCoords / _hitVerse / _hitChapter / _handleTap) ──
  ({double ix, double iy}) _imageCoords(Offset local) {
    // screen = image·baseScale·zoom + (tx,ty)  ⇒  image = (local-(tx,ty))/(baseScale·zoom)
    final eff = baseScale * zoom;
    return (ix: (local.dx - tx) / eff, iy: (local.dy - ty) / eff);
  }

  /// The verse at (ix, iy), or else the nearest one within 1.2 of its height;
  /// [exact] takes only a verse whose box holds the point.
  int? _hitVerse(double ix, double iy, {bool exact = false}) {
    final ids = data.versesOnPage(currentPage);
    int? nearId;
    double nearD = double.infinity, nearH = 0;
    for (final id in ids) {
      final b = data.getBox(id);
      if (b == null) continue;
      if (ix >= b.x && ix <= b.x + b.w && iy >= b.y && iy <= b.y + b.h) {
        return id;
      }
      final cx = b.x + b.w / 2, cy = b.y + b.h / 2;
      final d = math.sqrt(math.pow(ix - cx, 2) + math.pow(iy - cy, 2));
      if (d < nearD) {
        nearD = d;
        nearId = id;
        nearH = b.h;
      }
    }
    return !exact && nearD < nearH * 1.2 ? nearId : null;
  }

  int? _hitChapter(double ix, double iy) {
    for (final idx in data.chaptersOnPage(currentPage)) {
      final b = data.chapterBox(idx);
      if (b == null) continue;
      if (ix >= b.left && ix <= b.right && iy >= b.top && iy <= b.bottom) {
        return idx;
      }
    }
    return null;
  }

  void _handleTap(Offset local) {
    final p = _imageCoords(local);
    // A verse box wins over a heading box (ADR 0011, F-03): a heading rectangle that
    // strays over a verse must not hide it. Then the heading, then the nearest verse.
    final inVerse = _hitVerse(p.ix, p.iy, exact: true);
    final chap = inVerse == null ? _hitChapter(p.ix, p.iy) : null;
    if (chap != null) {
      _chapterTap.add(chap);
      return;
    }
    final hit = inVerse ?? _hitVerse(p.ix, p.iy);
    if (hit == null) {
      _pageTap.add(null);
      return;
    }
    final b = data.getBox(hit);
    if (b != null) {
      pulse = (box: Rect.fromLTWH(b.x, b.y, b.w, b.h), start: _animNow());
      _invalidate();
    }
    _verseTap.add(hit);
  }

  /// A screen reader's «activate» on verse [id]: what a tap on it does.
  void activateVerse(int id) {
    _pulseOn(id);
    _verseTap.add(id);
  }

  /// A screen reader's long press on verse [id]: its menu, as a held touch opens it.
  void holdVerse(int id) {
    _pulseOn(id);
    _verseLongPress.add(id);
  }

  void _pulseOn(int id) {
    final b = data.getBox(id);
    if (b == null) return;
    pulse = (box: Rect.fromLTWH(b.x, b.y, b.w, b.h), start: _animNow());
    _invalidate();
  }

  void _doubleTapZoom(Offset local) {
    if (zoom > 1.05) {
      resetView(true);
      return;
    }
    final p = _imageCoords(local);
    final hit = _hitVerse(p.ix, p.iy);
    final b = hit != null ? data.getBox(hit) : null;
    final box = b != null
        ? Rect.fromLTWH(b.x, b.y, b.w, b.h)
        : Rect.fromLTWH(p.ix, p.iy, 1, 1);
    _centerOnBox(box, zoom: 2.4, animate: true);
  }

  // ── gesture engine (ported: _bindGestures) — driven by raw pointer events ──
  final Map<int, Offset> _pts = {};
  String? _mode; // 'pan' | 'pinch' | 'swipe' | null
  double _startX = 0, _startY = 0, _startT = 0;
  bool _moved = false;
  double _panTx = 0, _panTy = 0;
  ({double dist0, double z0, double sx, double sy})? _pinch;
  double _lastX = 0, _lastY = 0, _lastMoveT = 0, _vx = 0, _vy = 0;
  // Never a double tap before the first tap: the clock starts at construction.
  ({double t, double x, double y}) _lastTap = (t: double.negativeInfinity, x: 0, y: 0);
  Timer? _longPressTimer;
  bool _longPressed = false;

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _armLongPress(Offset local) {
    _cancelLongPress();
    _longPressed = false;
    _longPressTimer = Timer(const Duration(milliseconds: kLongPressMs), () {
      if (_moved || _pts.length != 1) return;
      final p = _imageCoords(local);
      final hit = _hitVerse(p.ix, p.iy);
      if (hit == null) return;
      _longPressed = true;
      final b = data.getBox(hit);
      if (b != null) {
        pulse = (box: Rect.fromLTWH(b.x, b.y, b.w, b.h), start: _animNow());
        _invalidate();
      }
      HapticFeedback.selectionClick();
      _verseLongPress.add(hit);
    });
  }

  Offset _centroid() {
    double sx = 0, sy = 0;
    for (final p in _pts.values) {
      sx += p.dx;
      sy += p.dy;
    }
    final n = _pts.isEmpty ? 1 : _pts.length;
    return Offset(sx / n, sy / n);
  }

  double _spread() {
    final a = _pts.values.toList();
    if (a.length < 2) return 0;
    return (a[0] - a[1]).distance;
  }

  void pointerDown(int id, Offset local) {
    _stopMomentum();
    _pts[id] = local;
    if (_pts.length == 1) {
      _mode = null;
      _moved = false;
      _startX = _lastX = local.dx;
      _startY = _lastY = local.dy;
      _startT = _lastMoveT = _now();
      _panTx = tx;
      _panTy = ty;
      _vx = _vy = 0;
      _armLongPress(local);
    } else if (_pts.length == 2) {
      _cancelLongPress();
      _mode = 'pinch';
      _moved = true;
      final c = _centroid();
      _pinch = (
        dist0: _spread() == 0 ? 1 : _spread(),
        z0: zoom,
        sx: (c.dx - tx) / zoom,
        sy: (c.dy - ty) / zoom,
      );
    }
  }

  void pointerMove(int id, Offset local) {
    if (!_pts.containsKey(id)) return;
    _pts[id] = local;

    if (_mode == 'pinch' && _pts.length >= 2) {
      final c = _centroid();
      final z = clampd(
        (_pinch!.z0 * _spread()) / _pinch!.dist0,
        _minZoom,
        _maxZoom,
      );
      final nx = c.dx - _pinch!.sx * z;
      final ny = c.dy - _pinch!.sy * z;
      _setView(z, nx, ny, false);
      return;
    }

    if (_pts.length != 1) return;
    final dx = local.dx - _startX;
    final dy = local.dy - _startY;
    if (!_moved && (Offset(dx, dy)).distance > _tapSlop) {
      _moved = true;
      _cancelLongPress();
    }
    if (!_moved) return;

    final zoomed = zoom > 1.02;
    final canPanX = baseW * zoom > viewW + 1;
    final canPanY = baseH * zoom > viewH + 1;
    if (_mode == null) {
      if (zoomed && (canPanX || canPanY)) {
        _mode = 'pan';
      } else if (canPanY && dy.abs() > dx.abs()) {
        _mode = 'pan';
      } else {
        _mode = 'swipe';
      }
    }

    if (_mode == 'pan') {
      final now = _now();
      final dt = math.max(1, now - _lastMoveT);
      _vx = (local.dx - _lastX) / dt;
      _vy = (local.dy - _lastY) / dt;
      _lastX = local.dx;
      _lastY = local.dy;
      _lastMoveT = now;
      _setView(
        zoom,
        canPanX ? _panTx + dx : tx,
        canPanY ? _panTy + dy : ty,
        false,
      );
    }
  }

  void pointerUp(int id, Offset local) {
    final had = _pts.containsKey(id);
    _pts.remove(id);
    if (!had) return;
    _cancelLongPress();
    if (_longPressed) {
      // The hold already opened the menu; the release is not a tap.
      _longPressed = false;
      _mode = null;
      return;
    }

    if (_mode == 'pinch') {
      if (zoom < 1.02) resetView(true);
      if (_pts.length == 1) {
        final rem = _pts.values.first;
        _mode = null;
        _moved = false;
        _startX = _lastX = rem.dx;
        _startY = _lastY = rem.dy;
        _startT = _lastMoveT = _now();
        _panTx = tx;
        _panTy = ty;
      }
      return;
    }

    if (_pts.isNotEmpty) return;

    final dx = local.dx - _startX;
    final dy = local.dy - _startY;
    final dt = _now() - _startT;

    if (_mode == 'swipe' || (_mode == null && dx.abs() > _swipeMin)) {
      if (dx.abs() > _swipeMin && dx.abs() > dy.abs() * 1.4) {
        _userGo(currentPage + (dx > 0 ? 1 : -1));
        _mode = null;
        return;
      }
    }

    if (_mode == 'pan') {
      _startMomentum(_vx, _vy);
      _mode = null;
      return;
    }

    // a tap
    if (!_moved && dx.abs() < _tapSlop && dy.abs() < _tapSlop && dt < 500) {
      final now = _now();
      final isDouble =
          now - _lastTap.t < _dblMs &&
          (Offset(local.dx - _lastTap.x, local.dy - _lastTap.y)).distance <
              _dblSlop;
      if (isDouble) {
        _lastTap = (t: double.negativeInfinity, x: 0, y: 0);
        _doubleTapZoom(local);
      } else {
        _lastTap = (t: now, x: local.dx, y: local.dy);
        _handleTap(local);
      }
    }
    _mode = null;
  }

  void pointerCancel(int id) {
    _cancelLongPress();
    _longPressed = false;
    _pts.remove(id);
    if (_pts.isEmpty) _mode = null;
  }

  // ── momentum (ported: _startMomentum / _stopMomentum) ──
  double _mvx = 0, _mvy = 0, _mLast = 0;
  void _startMomentum(double vx, double vy) {
    if (reduceMotion || _vsync == null) return;
    final speed = (Offset(vx, vy)).distance;
    if (speed < 0.04) return;
    _mvx = vx;
    _mvy = vy;
    _mLast = _now();
    _momentum?.dispose();
    _momentum = _vsync!.createTicker((_) {
      final now = _now();
      final dt = math.min(32, now - _mLast);
      _mLast = now;
      _mvx *= 0.94;
      _mvy *= 0.94;
      final beforeTx = tx, beforeTy = ty;
      _setView(zoom, tx + _mvx * dt, ty + _mvy * dt, false);
      final stuck = (tx - beforeTx).abs() < 0.1 && (ty - beforeTy).abs() < 0.1;
      if (!((Offset(_mvx, _mvy)).distance > 0.02 && !stuck)) {
        _momentum?.stop();
      }
    })..start();
  }

  void _stopMomentum() {
    _momentum?.stop();
  }

  /// The page behind the scan: the night page's own black at night (ADR 0020).
  Color get pageBg => night ? TzNightPage.pageBg : TzColors.paper.pageBg;

  @override
  void dispose() {
    _xform?.dispose();
    _overlay?.dispose();
    _momentum?.dispose();
    _cancelLongPress();
    _verseTap.close();
    _verseLongPress.close();
    _pageChange.close();
    _chapterTap.close();
    _pageTap.close();
    _viewPref.close();
    _openSearch.close();
    super.dispose();
  }
}

// ───────────────────────── widget ─────────────────────────

class PageViewer extends StatefulWidget {
  final PageViewerController controller;

  /// What a screen reader says for verse N (its text). With it, each verse on the
  /// page is one item for TalkBack / VoiceOver, placed over its box: activating it
  /// taps the verse, a long press opens its menu (features-v3 screen-reader-support).
  final String Function(int verse)? verseLabel;
  const PageViewer({super.key, required this.controller, this.verseLabel});

  /// The scan and the highlight are two layers, each behind its own repaint
  /// boundary (item 3.13): a new highlight never repaints the scan.
  static const imageKey = ValueKey('page-image-layer');
  static const overlayKey = ValueKey('page-highlight-layer');

  /// How often the stage and the image were built, and which pages were fetched
  /// ahead (for the performance tests).
  @visibleForTesting
  static int debugStageBuilds = 0, debugImageBuilds = 0;

  /// How often each layer was really painted (a repaint boundary's own counters
  /// also count the times only its parent was).
  @visibleForTesting
  static int debugImagePaints = 0, debugOverlayPaints = 0;
  @visibleForTesting
  static final Set<int> debugPrecached = {};

  @override
  State<PageViewer> createState() => PageViewerState();
}

class PageViewerState extends State<PageViewer> with TickerProviderStateMixin {
  PageViewerController get c => widget.controller;

  // What the stage and the image were last built from: a rebuild with the same
  // values hands back the same widgets, so nothing below them is touched.
  Object? _stageOf, _imageOf;
  Widget? _stage, _image;

  // The page whose scan has arrived. The highlight layer draws that page only,
  // so its boxes never sit on another page's scan.
  final _arrived = ValueNotifier<int>(0);
  int _watched = 0;
  ImageStream? _stream;
  late final ImageStreamListener _onImage = ImageStreamListener((_, _) => _arrived.value = _watched, onError: (_, _) {});

  /// The page the highlight layer is drawing: the one on screen once its scan is there.
  int get overlayPage => _arrived.value;

  @override
  void initState() {
    super.initState();
    c.attach(this);
  }

  @override
  void dispose() {
    _stream?.removeListener(_onImage);
    _arrived.dispose();
    c.detach(); // before super.dispose(): the mixin asserts its tickers are gone
    super.dispose();
  }

  /// Follows [page]'s scan until it is decoded, and fetches its neighbours ahead.
  void _watch(int page) {
    if (page == _watched) return;
    _watched = page;
    _stream?.removeListener(_onImage);
    // Already decoded (a neighbour fetched ahead): the listener is called at once.
    _stream = AssetImage(_pageAsset(page)).resolve(createLocalImageConfiguration(context))..addListener(_onImage);
    for (final n in [page - 1, page + 1]) {
      if (n < 1 || n > c.data.pageCount) continue;
      PageViewer.debugPrecached.add(n);
      precacheImage(AssetImage(_pageAsset(n)), context, onError: (_, _) {});
    }
  }

  String _pageAsset(int n) =>
      'assets/pages/page${n.toString().padLeft(3, '0')}.webp';

  @override
  Widget build(BuildContext context) {
    c.reduceMotion = MediaQuery.of(context).disableAnimations;
    return LayoutBuilder(
      builder: (context, constraints) {
        c.relayout(constraints.maxWidth, constraints.maxHeight);
        return ClipRect(
          child: Stack(
            children: [
              // the transformed stage (image + overlay). Chrome (toolbar / nav / page-no)
              // is overlaid by the home screen so immersive mode can animate it.
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => c.pointerDown(e.pointer, e.localPosition),
                onPointerMove: (e) => c.pointerMove(e.pointer, e.localPosition),
                onPointerUp: (e) => c.pointerUp(e.pointer, e.localPosition),
                onPointerCancel: (e) => c.pointerCancel(e.pointer),
                child: AnimatedBuilder(
                  animation: c,
                  builder: (context, _) => _buildStage(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStage() {
    if (c.baseW <= 0 || c.currentPage == 0) {
      return const SizedBox.expand();
    }
    _watch(c.currentPage);
    // Everything the stage is drawn from. The highlight's own moving parts (the
    // glide, a pulse, ribbons, a selection) are not here: they repaint its layer.
    final of = (
      c, c.currentPage, c.zoom, c.tx, c.ty, c.baseW, c.baseH, c.viewW, c.viewH, c.baseScale, //
      c.night, c.nightInk, c.pageBg, c.showPlaying, c.showBoxes, c.activeId, widget.verseLabel != null,
    );
    if (of == _stageOf && _stage != null) return _stage!;
    _stageOf = of;
    PageViewer.debugStageBuilds++;
    // column-major: scale(zoom) on x/y + translation (tx,ty) — avoids the deprecated
    // Matrix4.translate/scale helpers. screen = base·zoom + (tx,ty).
    final m = Matrix4(
      c.zoom,
      0,
      0,
      0, //
      0,
      c.zoom,
      0,
      0, //
      0,
      0,
      1,
      0, //
      c.tx,
      c.ty,
      0,
      1,
    );
    return _stage = SizedBox(
      width: c.viewW,
      height: c.viewH,
      child: Transform(
        transform: m,
        child: SizedBox(
          width: c.baseW,
          height: c.baseH,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.pageBg,
              // v2.css .page: 0 1px 2px and 0 10px 28px, both at 8 % black.
              boxShadow: [
                BoxShadow(color: TzColors.paper.ink.withValues(alpha: 0.08), offset: const Offset(0, 1), blurRadius: 2),
                BoxShadow(color: TzColors.paper.ink.withValues(alpha: 0.08), offset: const Offset(0, 10), blurRadius: 28),
              ],
            ),
            child: Stack(
              children: [
                _buildImage(),
                Positioned.fill(
                  child: RepaintBoundary(
                    key: PageViewer.overlayKey,
                    child: CustomPaint(
                      painter: _HighlightPainter(c, of, _arrived),
                      isComplex: false,
                    ),
                  ),
                ),
                if (widget.verseLabel case final label?)
                  for (final id in c.data.versesOnPage(c.currentPage))
                    if (c.data.getBox(id) case final b?)
                      Positioned(
                        left: b.x * c.baseScale,
                        top: b.y * c.baseScale,
                        width: b.w * c.baseScale,
                        height: b.h * c.baseScale,
                        // No hit area of its own: touches still reach the Listener above.
                        child: Semantics(
                          container: true,
                          label: label(id),
                          selected: c.activeId == id,
                          onTap: () => c.activateVerse(id),
                          onLongPress: () => c.holdVerse(id),
                          child: const SizedBox.expand(),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The scan, in its own layer: built again only for another page, size or ink.
  Widget _buildImage() {
    final of = (c, c.currentPage, c.baseW, c.baseH, c.night, c.nightInk);
    if (of == _imageOf && _image != null) return _image!;
    _imageOf = of;
    PageViewer.debugImageBuilds++;
    Widget image = Image.asset(
      _pageAsset(c.currentPage),
      width: c.baseW,
      height: c.baseH,
      fit: BoxFit.fill,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
    if (c.night) {
      image = ColorFiltered(
        colorFilter: ColorFilter.matrix(PageViewerController.nightPageMatrix(c.nightInk)),
        child: image,
      );
    }
    // The scan itself says nothing; the verses over it do.
    return _image = RepaintBoundary(key: PageViewer.imageKey, child: _PaintCount(child: ExcludeSemantics(child: image)));
  }
}

/// Counts the paints of the scan's layer (for the performance tests).
class _PaintCount extends SingleChildRenderObjectWidget {
  const _PaintCount({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPaintCount();
}

class _RenderPaintCount extends RenderProxyBox {
  @override
  void paint(PaintingContext context, Offset offset) {
    PageViewer.debugImagePaints++;
    super.paint(context, offset);
  }
}

/// The highlight layer's own signal.
class _Repaint extends ChangeNotifier {
  void now() => notifyListeners();
}

// ───────────────────────── overlay painter (ported: _render) ─────────────────────────
class _HighlightPainter extends CustomPainter {
  final PageViewerController c;

  /// What the stage was built from: the fields this painter was made for.
  final Object of;

  /// The page whose scan has arrived.
  final ValueNotifier<int> arrived;

  _HighlightPainter(this.c, this.of, this.arrived) : super(repaint: Listenable.merge([c.repaint, arrived]));

  @override
  void paint(Canvas canvas, Size size) {
    PageViewer.debugOverlayPaints++;
    // Another page's scan is still on screen: its boxes are not this page's.
    if (arrived.value != c.currentPage) return;
    final now = c._animNow();
    final col = _playingCol(c.night);
    final s = c.baseScale;

    if (c.showBoxes) _drawAllBoxes(canvas, col, s);
    if (c.selection != null) _drawSelection(canvas, c.selection!, s);
    if (c.ribbons.isNotEmpty) _drawRibbons(canvas, s);

    if (c.showPlaying) {
      if (c.playingRectAt(now) case final playing?) _drawPlaying(canvas, playing, s);
    }

    if (c.pulse != null) {
      final pp = clampd((now - c.pulse!.start) / _pulseMs, 0, 1);
      if (pp < 1) _drawPulse(canvas, c.pulse!.box, pp, col, s);
    }

    _drawChapterOverlay(canvas, s);
  }

  RRect _rrect(double x, double y, double w, double h, double r) {
    r = math.min(r, math.min(w / 2, h / 2));
    return RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, w, h),
      Radius.circular(r),
    );
  }

  /// The playing verse (v2.css .hl.play): the gilt wash on its box, 3 px corners,
  /// and a 3 px gilt mark in the margin at its start side, 6 px out, inset 4 px.
  void _drawPlaying(Canvas canvas, Rect b, double s) {
    final k = _pageTokens(c.night);
    canvas.drawRRect(_rrect(b.left * s, b.top * s, b.width * s, b.height * s, 3), Paint()..color = k.giltWash);
    final right = (b.left + b.width) * s, top = b.top * s, h = b.height * s;
    canvas.drawRRect(_rrect(right + 3, top + 4, 3, math.max(0, h - 8), 2), Paint()..color = k.gilt);
  }

  /// Dashed boxes around the selected verses on this page: accent blue on the page,
  /// gold on the night page (the prototype's `selC`). The playing verse draws over them.
  void _drawSelection(Canvas canvas, ({int from, int to}) sel, double s) {
    final color = c.night ? TzColors.night.action : TzColors.paper.lapis;
    final fill = Paint()..color = color.withValues(alpha: c.night ? 0.16 : 0.10);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    for (final id in c.data.versesOnPage(c.currentPage)) {
      if (id < sel.from || id > sel.to) continue;
      final b = c.data.getBox(id);
      if (b == null) continue;
      final rr = _rrect(b.x * s, b.y * s, b.w * s, b.h * s, 9);
      canvas.drawRRect(rr, fill);
      drawDashedRRect(canvas, rr, stroke);
    }
  }

  /// A bookmark's ribbon (v2.js page(), v2.css .ribbon): 8 × 18 with a notch at
  /// 72 %, hanging 3 px above the verse's box, 10 px in from its start (right) edge.
  void _drawRibbons(Canvas canvas, double s) {
    for (final id in c.data.versesOnPage(c.currentPage)) {
      final mark = c.ribbons[id];
      final r = c.ribbonBox(id, s);
      if (mark == null || r == null) continue;
      final path = Path()
        ..moveTo(r.left, r.top)
        ..lineTo(r.right, r.top)
        ..lineTo(r.right, r.bottom)
        ..lineTo(r.center.dx, r.top + r.height * 0.72)
        ..lineTo(r.left, r.bottom)
        ..close();
      canvas.drawPath(path, Paint()..color = _pageTokens(c.night).bookmarks[mark]);
    }
  }

  void _drawAllBoxes(Canvas canvas, _Col col, double s) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..color = col.ghost;
    for (final id in c.data.versesOnPage(c.currentPage)) {
      if (id == c.activeId) continue;
      final b = c.data.getBox(id);
      if (b == null) continue;
      canvas.drawRRect(_rrect(b.x * s, b.y * s, b.w * s, b.h * s, 8), stroke);
    }
  }

  void _drawChapterOverlay(Canvas canvas, double s) {
    final onPage = c.data.chaptersOnPage(c.currentPage);
    if (onPage.isEmpty) return;
    if (c.chapterHover != null &&
        c.chapterHover != c.chapterSel &&
        onPage.contains(c.chapterHover)) {
      _drawChapterBox(
        canvas,
        c.chapterHover!,
        _pageTokens(c.night).lapisWash,
        _pageTokens(c.night).lapis.withValues(alpha: 0.65),
        1.5,
        true,
        s,
      );
    }
    if (c.chapterSel != null && onPage.contains(c.chapterSel)) {
      _drawChapterBox(
        canvas,
        c.chapterSel!,
        _pageTokens(c.night).giltWash,
        _pageTokens(c.night).gilt,
        3,
        false,
        s,
      );
    }
  }

  void _drawChapterBox(
    Canvas canvas,
    int idx,
    Color fillC,
    Color strokeC,
    double lineW,
    bool dashed,
    double s,
  ) {
    final b = c.data.chapterBox(idx);
    if (b == null) return;
    final rr = _rrect(b.left * s, b.top * s, b.width * s, b.height * s, 3);
    canvas.drawRRect(rr, Paint()..color = fillC);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineW
      ..color = strokeC;
    if (dashed) {
      _drawDashedRRect(canvas, rr, stroke, 7, 5);
    } else {
      canvas.drawRRect(rr, stroke);
    }
  }

  void _drawDashedRRect(
    Canvas canvas,
    RRect rr,
    Paint paint,
    double dash,
    double gap,
  ) {
    final path = Path()..addRRect(rr);
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final len = math.min(dash, metric.length - dist);
        canvas.drawPath(metric.extractPath(dist, dist + len), paint);
        dist += dash + gap;
      }
    }
  }

  void _drawPulse(Canvas canvas, Rect b, double pp, _Col col, double s) {
    final grow = pp * 9;
    final x = b.left * s - grow,
        y = b.top * s - grow,
        w = b.width * s + grow * 2,
        h = b.height * s + grow * 2;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * (1 - pp) + 0.5
      ..color = col.stroke.withValues(alpha: col.stroke.a * (1 - pp) * 0.9);
    canvas.drawRRect(_rrect(x, y, w, h, 11), stroke);
  }

  @override
  bool shouldRepaint(covariant _HighlightPainter old) => old.c != c || old.of != of || old.arrived != arrived;
}

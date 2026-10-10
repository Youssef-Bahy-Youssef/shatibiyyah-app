// lib/ui/reader/fixed_page_layout.dart — where the manuscript page sits (features-v3 fixed-page-layout).
//
// The page is laid out once, as if the top bar and the dock were always shown,
// so hiding or showing them (immersive mode), highlighting, masking or swiping
// never moves or resizes the page — and neither ever covers it. Only the
// student's own pinch / double-tap zoom changes the view.
//
// The zones are the prototype's (item 3.4, v2.css .topbar, .page, .dock, on a
// 390×844 phone with a 44 px status bar and a 34 px home indicator): the top bar
// directly under the status bar, 56 px; the page from 100 to 674; the dock
// (62 + 54) 28 px above the bottom edge, 10 px from the sides.
//
//   topZone    = safeTop + barHeight
//   bottomZone = dockBottom(safeBottom) + dockHeight + zoneGap
//   pageW      = min(W − 2·side, (H − topZone − bottomZone) · 1130/1735)
//   pageH      = pageW · 1735/1130, centred in the space between the zones
import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:flutter/widgets.dart' show EdgeInsets;

/// The layout tokens of the reader's chrome.
class ReaderTokens {
  static const double barHeight = 56;
  static const double zoneGap = 26;
  static const double dockRowHeight = 62;
  static const double dockTabsHeight = 54;
  static const double dockHeight = dockRowHeight + dockTabsHeight;
  static const double dockSide = 10;
  static const double sideMargin = 8;

  /// Text mode's distance from the bar and the dock.

  /// The dock floats this far up into the home indicator's inset, and never
  /// nearer the edge than [dockMinBottom].
  static const double dockLift = 6;
  static const double dockMinBottom = 12;
  static const double pageAspect = 1130 / 1735;

  /// How far the dock floats above the bottom edge: 28 px over a 34 px home
  /// indicator, never under 12.
  static double dockBottom(double safeBottom) => math.max(dockMinBottom, safeBottom - dockLift);

  /// What a scrolling list keeps clear at its end, so the dock never hides its
  /// last row (v2.css .list padding-bottom): the dock, its offset and 14 px.
  static double dockInset(double safeBottom, {bool nowPlaying = true}) =>
      dockBottom(safeBottom) + (nowPlaying ? dockHeight : dockTabsHeight) + 14;
}

class ReaderLayout {
  /// The page rectangle (never changes with the chrome).
  final Rect page;

  /// The top bar's rectangle and the dock's.
  final Rect bar;
  final Rect dock;
  final Size screen;

  const ReaderLayout(this.page, this.bar, this.dock, this.screen);

  /// Text mode's zone: from the top bar to the screen's end. The column scrolls
  /// under the dock (v2.css .scr, .tm).
  Rect get textZone => Rect.fromLTRB(0, bar.bottom, screen.width, screen.height);

  /// What the dock covers at the end of text mode's column, and the gap above
  /// it: the column's last verse scrolls clear of both (v2.css .tm padding-bottom).
  double get textInset => screen.height - dock.top + ReaderTokens.zoneGap;

  factory ReaderLayout.compute(Size screen, EdgeInsets safe) {
    final dockBottom = ReaderTokens.dockBottom(safe.bottom);
    final topZone = safe.top + ReaderTokens.barHeight;
    final bottomZone = dockBottom + ReaderTokens.dockHeight + ReaderTokens.zoneGap;
    final availW = screen.width - 2 * ReaderTokens.sideMargin;
    final availH = math.max(0.0, screen.height - topZone - bottomZone);
    final pageW = math.min(availW, availH * ReaderTokens.pageAspect);
    final pageH = pageW / ReaderTokens.pageAspect;
    final left = (screen.width - pageW) / 2;
    final top = topZone + (availH - pageH) / 2;
    return ReaderLayout(
      Rect.fromLTWH(left, top, pageW, pageH),
      Rect.fromLTWH(0, safe.top, screen.width, ReaderTokens.barHeight),
      Rect.fromLTWH(ReaderTokens.dockSide, screen.height - dockBottom - ReaderTokens.dockHeight,
          screen.width - 2 * ReaderTokens.dockSide, ReaderTokens.dockHeight),
      screen,
    );
  }
}

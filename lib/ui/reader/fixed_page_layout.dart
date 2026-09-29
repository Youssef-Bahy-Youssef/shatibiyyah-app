// lib/ui/reader/fixed_page_layout.dart — where the manuscript page sits (features-v3 fixed-page-layout).
//
// The page is laid out once, as if the top bar and the player were always shown,
// so hiding or showing them (immersive mode), highlighting, masking or swiping
// never moves or resizes the page — and neither bar ever covers it. Only the
// student's own pinch / double-tap zoom changes the view.
//
//   topZone    = safeTop + barGap + barHeight + zoneGap
//   bottomZone = safeBottom + playerHeight + zoneGap
//   pageW      = min(W − 2·side, (H − topZone − bottomZone) · 1130/1735)
//   pageH      = pageW · 1735/1130, centred in the space between the zones
import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:flutter/widgets.dart' show EdgeInsets;

/// The v3 layout tokens (features-v3.json `layout_tokens`).
class ReaderTokens {
  static const double barGap = 4;
  static const double barHeight = 52;
  static const double zoneGap = 10;
  static const double playerHeight = 96;
  static const double sideMargin = 8;
  static const double pageAspect = 1130 / 1735;
}

class ReaderLayout {
  /// The page rectangle (never changes with the chrome).
  final Rect page;

  /// The top bar's rectangle and the player's rectangle.
  final Rect bar;
  final Rect player;

  const ReaderLayout(this.page, this.bar, this.player);

  factory ReaderLayout.compute(Size screen, EdgeInsets safe) {
    final topZone = safe.top + ReaderTokens.barGap + ReaderTokens.barHeight + ReaderTokens.zoneGap;
    final bottomZone = safe.bottom + ReaderTokens.playerHeight + ReaderTokens.zoneGap;
    final availW = screen.width - 2 * ReaderTokens.sideMargin;
    final availH = math.max(0.0, screen.height - topZone - bottomZone);
    final pageW = math.min(availW, availH * ReaderTokens.pageAspect);
    final pageH = pageW / ReaderTokens.pageAspect;
    final left = (screen.width - pageW) / 2;
    final top = topZone + (availH - pageH) / 2;
    return ReaderLayout(
      Rect.fromLTWH(left, top, pageW, pageH),
      Rect.fromLTWH(0, safe.top + ReaderTokens.barGap, screen.width, ReaderTokens.barHeight),
      Rect.fromLTWH(0, screen.height - safe.bottom - ReaderTokens.playerHeight, screen.width,
          ReaderTokens.playerHeight),
    );
  }
}

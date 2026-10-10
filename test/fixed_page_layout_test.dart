// The fixed page layout against the prototype's phone (v2.css: a 390×844 screen,
// 44 px status bar, 34 px home indicator → the page 374×574 at (8, 100), the dock
// 116 px high 28 px above the edge) and two derived cases.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/reader/fixed_page_layout.dart';

void main() {
  void expectRect(Rect r, double l, double t, double w, double h) {
    expect(r.left, closeTo(l, 0.5));
    expect(r.top, closeTo(t, 0.5));
    expect(r.width, closeTo(w, 0.5));
    expect(r.height, closeTo(h, 0.5));
  }

  test('the prototype: 390×844 (insets 44/34): the page 374×574 at (8, 100), the dock at 700', () {
    final l = ReaderLayout.compute(const Size(390, 844), const EdgeInsets.only(top: 44, bottom: 34));
    expectRect(l.page, 8, 100, 374, 574);
    expectRect(l.bar, 0, 44, 390, 56);
    expectRect(l.dock, 10, 700, 370, 116);
  });

  test('390×844 (insets 40/20): 374×574 at (8, 105)', () {
    final l = ReaderLayout.compute(const Size(390, 844), const EdgeInsets.only(top: 40, bottom: 20));
    expectRect(l.page, 8, 104.9, 374, 574.2);
  });

  test('360×640 (insets 24/16): 264×406 at (48, 80)', () {
    final l = ReaderLayout.compute(const Size(360, 640), const EdgeInsets.only(top: 24, bottom: 16));
    expectRect(l.page, 47.8, 80, 264.4, 406);
  });

  test('neither the bar nor the dock overlaps the page, on any common phone', () {
    for (final (size, safe) in [
      (const Size(390, 844), const EdgeInsets.only(top: 47, bottom: 34)),
      (const Size(412, 915), const EdgeInsets.only(top: 24, bottom: 24)),
      (const Size(360, 640), const EdgeInsets.only(top: 24, bottom: 0)),
      (const Size(430, 932), const EdgeInsets.only(top: 59, bottom: 34)),
    ]) {
      final l = ReaderLayout.compute(size, safe);
      expect(l.page.top, greaterThanOrEqualTo(l.bar.bottom - 0.01), reason: '$size');
      expect(l.page.bottom, lessThanOrEqualTo(l.dock.top - ReaderTokens.zoneGap + 0.01), reason: '$size');
      expect(l.page.width / l.page.height, closeTo(1130 / 1735, 1e-9));
      expect(l.dock.height, ReaderTokens.dockHeight);
      expect(l.dock.bottom, size.height - ReaderTokens.dockBottom(safe.bottom));
    }
  });
}

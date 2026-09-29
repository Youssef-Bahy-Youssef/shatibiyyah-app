// The fixed page layout against the two worked examples in features-v3.json.
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

  test('390×844 (insets 40/20): 374×574 at (8, 125)', () {
    final l = ReaderLayout.compute(const Size(390, 844), const EdgeInsets.only(top: 40, bottom: 20));
    expectRect(l.page, 8, 124.9, 374, 574.2);
  });

  test('360×640 (insets 24/16): 279×428 at (41, 90)', () {
    final l = ReaderLayout.compute(const Size(360, 640), const EdgeInsets.only(top: 24, bottom: 16));
    expectRect(l.page, 40.6, 90, 278.8, 428);
  });

  test('neither bar overlaps the page, on any common phone', () {
    for (final (size, safe) in [
      (const Size(390, 844), const EdgeInsets.only(top: 47, bottom: 34)),
      (const Size(412, 915), const EdgeInsets.only(top: 24, bottom: 24)),
      (const Size(360, 640), const EdgeInsets.only(top: 24, bottom: 0)),
      (const Size(430, 932), const EdgeInsets.only(top: 59, bottom: 34)),
    ]) {
      final l = ReaderLayout.compute(size, safe);
      expect(l.page.top, greaterThanOrEqualTo(l.bar.bottom + ReaderTokens.zoneGap - 0.01), reason: '$size');
      expect(l.page.bottom, lessThanOrEqualTo(l.player.top - ReaderTokens.zoneGap + 0.01), reason: '$size');
      expect(l.page.width / l.page.height, closeTo(1130 / 1735, 1e-9));
      expect(l.player.height, ReaderTokens.playerHeight);
    }
  });
}

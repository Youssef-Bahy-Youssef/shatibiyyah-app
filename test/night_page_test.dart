// Item 3.5 (ADR 0020): at night the scan is drawn through the chosen ink's 4×5
// matrix from the tokens, not the old invert/sepia; the brightness setting only
// scales the colour rows.
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';

void main() {
  test('at full brightness the night matrix is the ink\'s matrix, exactly', () {
    for (final ink in TzNightPage.inks) {
      expect(PageViewerController.nightPageMatrix(ink, 1), ink.matrix, reason: ink.id);
    }
  });

  test('brightness scales the colour rows, not the alpha row', () {
    final m = PageViewerController.nightPageMatrix(TzNightPage.jade, 0.5);
    final j = TzNightPage.jade.matrix;
    for (var i = 0; i < 15; i++) {
      expect(m[i], closeTo(j[i] * 0.5, 1e-9), reason: 'cell $i');
    }
    expect(m.sublist(15), j.sublist(15));
  });
}

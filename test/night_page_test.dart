// Item 3.5 (ADR 0020): at night the scan is drawn through the chosen ink's 4×5
// matrix from the tokens, not the old invert/sepia. The tokens hold it as an
// SVG feColorMatrix (offsets on a 0…1 scale); Flutter's ColorFilter.matrix takes
// the offset column on 0…255. What matters is what it does to the scan: white
// paper becomes the night page's black, black ink its ivory, and the booklet's
// coloured ink the chosen accent.
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';

/// [m] applied to an opaque colour, as ColorFilter.matrix does (channels 0…255).
Color through(List<double> m, int r, int g, int b) {
  int row(int i) => (m[i] * r + m[i + 1] * g + m[i + 2] * b + m[i + 3] * 255 + m[i + 4]).round().clamp(0, 255);
  return Color.fromARGB(255, row(0), row(5), row(10));
}

int _c(double v) => (v * 255).round();
List<int> _rgb(Color c) => [_c(c.r), _c(c.g), _c(c.b)];

void main() {
  test('every ink: white paper becomes the night page, black ink its ivory', () {
    for (final ink in TzNightPage.inks) {
      final m = PageViewerController.nightPageMatrix(ink, 1);
      expect(_rgb(through(m, 255, 255, 255)), _rgb(TzNightPage.pageBg), reason: '${ink.id}: paper');
      expect(_rgb(through(m, 0, 0, 0)), _rgb(TzNightPage.pageInk), reason: '${ink.id}: ink');
    }
  });

  test('the booklet\'s crimson ink comes out as the chosen accent, within a few levels', () {
    // The scan's coloured ink, as printed (the rubric on paper): #C2185B-like crimson.
    // tools/night_page_accent.py solves each matrix so that this maps to the accent.
    const printed = [0xD8, 0x1B, 0x60];
    for (final ink in TzNightPage.inks) {
      final out = _rgb(through(PageViewerController.nightPageMatrix(ink, 1), printed[0], printed[1], printed[2]));
      final want = _rgb(ink.accent);
      for (var i = 0; i < 3; i++) {
        expect((out[i] - want[i]).abs(), lessThanOrEqualTo(40), reason: '${ink.id} channel $i: $out vs $want');
      }
      // And it is the accent's hue, not grey: its strongest channel is the accent's.
      expect(out.indexOf(out.reduce((a, b) => a > b ? a : b)), want.indexOf(want.reduce((a, b) => a > b ? a : b)), reason: ink.id);
    }
  });

  test('the matrix is the token matrix with its offset column on Flutter\'s scale', () {
    final m = PageViewerController.nightPageMatrix(TzNightPage.jade, 1), j = TzNightPage.jade.matrix;
    for (var i = 0; i < 20; i++) {
      expect(m[i], closeTo(i % 5 == 4 ? j[i] * 255 : j[i], 1e-9), reason: 'cell $i');
    }
  });

  test('brightness scales the colour rows, not the alpha row', () {
    final full = PageViewerController.nightPageMatrix(TzNightPage.jade, 1);
    final half = PageViewerController.nightPageMatrix(TzNightPage.jade, 0.5);
    for (var i = 0; i < 15; i++) {
      expect(half[i], closeTo(full[i] * 0.5, 1e-9), reason: 'cell $i');
    }
    expect(half.sublist(15), full.sublist(15));
  });
}

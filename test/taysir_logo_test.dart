// The logo's painter (ADR 0028): its colours are tokens, and in one colour (the
// Android notification icon, which the system reads as alpha only) the mark keeps its
// text lines as holes instead of filling into a blank shape.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/taysir_logo.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';

const _px = 240;

/// The painter's picture as straight RGBA bytes, [_px] square.
Future<Uint8List> _render(TaysirLogoPainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size.square(_px + 0.0));
  final image = await recorder.endRecording().toImage(_px, _px);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  return bytes!.buffer.asUint8List();
}

void main() {
  test('the painter holds no colour literal', () {
    final source = File('lib/ui/design/taysir_logo.dart').readAsStringSync();
    expect(RegExp(r'\bColor\(0x|\bColor\.from|\bColors\.').allMatches(source), isEmpty);
  });

  testWidgets('in one colour the mark is that colour only, and its lines are holes', (tester) async {
    late Uint8List full, flat;
    await tester.runAsync(() async {
      full = await _render(const TaysirLogoPainter());
      flat = await _render(const TaysirLogoPainter(silhouette: Color.fromARGB(255, 255, 255, 255)));
    });
    final line = TzColors.paper.cover; // the lines' colour on the binding
    final want = [for (final v in [line.r, line.g, line.b]) (v * 255).round()];
    bool isLine(int x, int y) {
      if (x < 0 || y < 0 || x >= _px || y >= _px) return false;
      final i = (y * _px + x) * 4;
      return full[i + 3] == 255 && full[i] == want[0] && full[i + 1] == want[1] && full[i + 2] == want[2];
    }

    var drawn = 0, inLines = 0, filled = 0;
    for (var y = 0; y < _px; y++) {
      for (var x = 0; x < _px; x++) {
        final i = (y * _px + x) * 4;
        if (flat[i + 3] > 0) {
          drawn++;
          expect(flat.sublist(i, i + 3), [255, 255, 255], reason: 'pixel $x, $y');
        }
        // A pixel inside a line, not on its antialiased edge: its four neighbours are line too.
        if (isLine(x, y) && isLine(x - 1, y) && isLine(x + 1, y) && isLine(x, y - 1) && isLine(x, y + 1)) {
          inLines++;
          if (flat[i + 3] > 0) filled++;
        }
      }
    }
    expect(drawn, greaterThan(_px * _px ~/ 5), reason: 'the silhouette is drawn');
    expect(inLines, greaterThan(_px * _px ~/ 50), reason: 'the full mark has its lines');
    expect(filled, 0, reason: 'the inside of a line is a hole in the silhouette');
  });
}

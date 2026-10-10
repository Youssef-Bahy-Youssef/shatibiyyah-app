// lib/ui/design/components/phrase_wash.dart — words of a line of text lit from
// behind: a quoted phrase in the gilt wash (v2.css mark.mqhl), the chosen reader
// symbol in the lapis wash (v2.css .rb.sym.on). Rounded, wider than the words
// all round. Painted under the text, so the words keep their own inks (a rubric
// name inside a lit phrase stays rubric).
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// One wash: the words (offsets into the text), its colour, how far it reaches
/// past the words and its corner radius.
typedef Wash = ({int start, int end, Color color, double spread, double radius});

class PhraseWash extends SingleChildRenderObjectWidget {
  final List<Wash> washes;

  /// The child is the text itself (a [RichText]).
  const PhraseWash({super.key, required this.washes, required RichText super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderPhraseWash(washes);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) =>
      (renderObject as RenderPhraseWash).washes = washes;
}

class RenderPhraseWash extends RenderProxyBox {
  RenderPhraseWash(this._washes);

  List<Wash> _washes;
  set washes(List<Wash> value) {
    if (listEquals(value, _washes)) return;
    _washes = value;
    markNeedsPaint();
  }

  /// The box of the words [start]..[end], one per line they run over.
  List<Rect> boxesOf(int start, int end) {
    final text = child;
    if (text is! RenderParagraph || start >= end) return const [];
    final boxes = text.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end),
        boxHeightStyle: ui.BoxHeightStyle.tight);
    final lines = <Rect>[];
    for (final b in boxes) {
      final r = b.toRect();
      final i = lines.indexWhere((l) => l.top < r.bottom && r.top < l.bottom);
      i < 0 ? lines.add(r) : lines[i] = lines[i].expandToInclude(r);
    }
    return lines;
  }

  /// What is painted behind the text (for tests too).
  List<(RRect, Color)> get painted => [
        for (final w in _washes)
          for (final line in boxesOf(w.start, w.end))
            (RRect.fromRectAndRadius(line.inflate(w.spread), Radius.circular(w.radius)), w.color),
      ];

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final (box, color) in painted) {
      context.canvas.drawRRect(box.shift(offset), Paint()..color = color);
    }
    super.paint(context, offset);
  }
}

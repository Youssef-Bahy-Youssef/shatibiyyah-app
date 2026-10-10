// lib/ui/design/components/phrase_wash.dart — a phrase of a line of text lit from
// behind (v2.css mark.mqhl): the gilt wash, rounded, 2 px wider than the words
// all round. Painted under the text, so the words keep their own inks (a rubric
// name inside the phrase stays rubric).
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class PhraseWash extends SingleChildRenderObjectWidget {
  /// The phrase, as offsets into the child's text; null for none.
  final ({int start, int end})? range;
  final Color color;

  /// The child is the text itself (a [RichText]).
  const PhraseWash({super.key, required this.range, required this.color, required RichText super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPhraseWash(range, color);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) => (renderObject as _RenderPhraseWash)
    ..range = range
    ..color = color;
}

class _RenderPhraseWash extends RenderProxyBox {
  _RenderPhraseWash(this._range, this._color);

  ({int start, int end})? _range;
  set range(({int start, int end})? value) {
    if (value == _range) return;
    _range = value;
    markNeedsPaint();
  }

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  /// The washed boxes, one per line the phrase runs over (for tests too).
  List<RRect> get washes {
    final text = child, range = _range;
    if (text is! RenderParagraph || range == null || range.start >= range.end) return const [];
    final boxes = text.getBoxesForSelection(TextSelection(baseOffset: range.start, extentOffset: range.end),
        boxHeightStyle: ui.BoxHeightStyle.tight);
    final lines = <Rect>[];
    for (final b in boxes) {
      final r = b.toRect();
      final i = lines.indexWhere((l) => l.top < r.bottom && r.top < l.bottom);
      i < 0 ? lines.add(r) : lines[i] = lines[i].expandToInclude(r);
    }
    return [for (final l in lines) RRect.fromRectAndRadius(l.inflate(2), const Radius.circular(6))];
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final paint = Paint()..color = _color;
    for (final wash in washes) {
      context.canvas.drawRRect(wash.shift(offset), paint);
    }
    super.paint(context, offset);
  }
}

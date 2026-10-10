// lib/ui/design/components/phrase_wash.dart — what is painted behind a line of
// text, so the words keep their own inks and no glyph moves: a quoted phrase in
// the gilt wash (v2.css mark.mqhl), and the frame a reader symbol sits in
// (ADR 0024; v2.css .sf, tokens.json symbolFrame).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../tokens.g.dart';

/// One wash: the words (offsets into the text), its colour, how far it reaches
/// past the words and its corner radius.
typedef Wash = ({int start, int end, Color color, double spread, double radius});

/// A reader symbol to frame: its letters (offsets into the text), the tint and
/// the line. At rest the line is a hairline just inside the box; with [ring]
/// (the symbol's tip is open) it is drawn solid around it.
typedef FrameMark = ({int start, int end, Color fill, Color line, double lineWidth, bool ring});

/// A frame as it is painted.
typedef SymbolFrame = ({RRect box, Color fill, Color line, double lineWidth, bool ring});

/// How far a symbol's frame reaches above and below the baseline at a verse size
/// of [em]. On lines set tighter than the frame is tall (the share card's dense
/// layouts) it shrinks in proportion, so frames on neighbouring lines never meet.
({double above, double below}) symbolFrameReach({required double em, double? lineHeight}) {
  final above = TzSymbolFrame.above * em, below = TzSymbolFrame.below * em;
  final room = lineHeight == null ? double.infinity : lineHeight - TzSymbolFrame.lineGap * em;
  final k = math.min(1.0, room / (above + below));
  return (above: above * k, below: below * k);
}

class PhraseWash extends SingleChildRenderObjectWidget {
  final List<Wash> washes;
  final List<FrameMark> frames;

  /// The text's size and the height of its lines, which the frames are sized from.
  final double em;
  final double? lineHeight;

  /// The child is the text itself (a [RichText]).
  const PhraseWash(
      {super.key, required this.washes, this.frames = const [], this.em = 0, this.lineHeight, required RichText super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderPhraseWash(washes, frames, em, lineHeight);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) => (renderObject as RenderPhraseWash)
    ..washes = washes
    ..marks = frames
    ..em = em
    ..lineHeight = lineHeight;
}

class RenderPhraseWash extends RenderProxyBox {
  RenderPhraseWash(this._washes, [this._marks = const [], this._em = 0, this._lineHeight]);

  List<Wash> _washes;
  set washes(List<Wash> value) {
    if (listEquals(value, _washes)) return;
    _washes = value;
    markNeedsPaint();
  }

  List<FrameMark> _marks;
  set marks(List<FrameMark> value) {
    if (listEquals(value, _marks)) return;
    _marks = value;
    markNeedsPaint();
  }

  double _em;
  set em(double value) {
    if (value == _em) return;
    _em = value;
    markNeedsPaint();
  }

  double? _lineHeight;
  set lineHeight(double? value) {
    if (value == _lineHeight) return;
    _lineHeight = value;
    markNeedsPaint();
  }

  // From the top of a line's letter box down to its baseline: the same on every line of one face.
  double? _ascent;

  @override
  void performLayout() {
    super.performLayout();
    final text = child;
    _ascent = null;
    if (text is! RenderParagraph) return;
    final baseline = text.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true);
    // The first line's letter box: the whole text is asked for, as half a letter and its vowel has no box.
    final lines = boxesOf(0, text.text.toPlainText().length);
    if (baseline == null || lines.isEmpty) return;
    _ascent = baseline - lines.map((l) => l.top).reduce(math.min);
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

  /// The washes painted behind the text (for tests too).
  List<(RRect, Color)> get painted => [
        for (final w in _washes)
          for (final line in boxesOf(w.start, w.end))
            (RRect.fromRectAndRadius(line.inflate(w.spread), Radius.circular(w.radius)), w.color),
      ];

  /// The symbol frames painted behind the text, under the washes (for tests too).
  List<SymbolFrame> get frames {
    final ascent = _ascent;
    if (ascent == null || _marks.isEmpty) return const [];
    final reach = symbolFrameReach(em: _em, lineHeight: _lineHeight);
    final pad = TzSymbolFrame.pad * _em;
    return [
      for (final m in _marks)
        for (final line in boxesOf(m.start, m.end))
          (
            box: RRect.fromRectAndRadius(
              Rect.fromLTRB(line.left - pad, line.top + ascent - reach.above, line.right + pad, line.top + ascent + reach.below),
              Radius.circular(math.min(TzSymbolFrame.radius * _em, (line.width + 2 * pad) / 2)),
            ),
            fill: m.fill,
            line: m.line,
            lineWidth: m.lineWidth,
            ring: m.ring,
          ),
    ];
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    for (final f in frames) {
      final box = f.box.shift(offset);
      if (f.fill.a > 0) canvas.drawRRect(box, Paint()..color = f.fill);
      canvas.drawRRect(
        f.ring ? box.inflate(f.lineWidth / 2) : box.deflate(f.lineWidth / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = f.lineWidth
          ..color = f.line,
      );
    }
    for (final (box, color) in painted) {
      canvas.drawRRect(box.shift(offset), Paint()..color = color);
    }
    super.paint(context, offset);
  }
}

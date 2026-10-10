// lib/ui/design/components/anchored_popover.dart — the one popover for verses
// and chapter headings (item 3.3, ADRs 0011, 0019; v2.css .pop).
//
// Placed inside a Stack that covers the screen: 12 px from its sides, 12 px
// below the anchor, or above it when the body would not fit (the dock's height
// can be kept clear with [avoidBottom]). When it fits on neither side (a small
// phone, a verse at the page's foot) it takes the roomier side and is kept on
// the screen, which may cover the anchor's edge. A 14 px arrow points at the
// anchor's centre. It grows from the arrow in 200 ms (opacity, 6 px and
// 96 % → 100 %), instantly under reduced motion.
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../tokens.g.dart';
import '../tz_theme.dart';
import 'tz_motion.dart';

class AnchoredPopover extends StatefulWidget {
  /// The tapped verse or heading, in the coordinates of the popover's Stack.
  final Rect anchor;
  final Widget child;

  /// Room kept clear at the bottom (e.g. the dock).
  final double avoidBottom;

  /// The body's padding (v2.css .pop: 14 14 8).
  final EdgeInsets padding;

  const AnchoredPopover(
      {super.key,
      required this.anchor,
      required this.child,
      this.avoidBottom = 0,
      this.padding = const EdgeInsets.fromLTRB(14, 14, 14, 8)});

  static const bodyKey = ValueKey('anchored-popover-body');

  @override
  State<AnchoredPopover> createState() => _AnchoredPopoverState();
}

class _AnchoredPopoverState extends State<AnchoredPopover> with SingleTickerProviderStateMixin {
  AnimationController? _grow;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _grow ??= AnimationController(vsync: this, duration: tzDuration(context, TzMotion.medium))..forward();
  }

  @override
  void dispose() {
    _grow?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final grow = CurvedAnimation(parent: _grow!, curve: TzMotion.standard);
    return AnimatedBuilder(
      animation: grow,
      builder: (context, child) => AnchoredPopoverLayout(
        anchor: widget.anchor,
        avoidBottom: widget.avoidBottom,
        arrowColor: c.raised,
        progress: grow.value,
        child: child!,
      ),
      child: Semantics(
        container: true,
        child: Container(
          key: AnchoredPopover.bodyKey,
          padding: widget.padding,
          decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(18), boxShadow: c.float),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Lays the popover's body out against its anchor and draws the arrow.
class AnchoredPopoverLayout extends SingleChildRenderObjectWidget {
  final Rect anchor;
  final double avoidBottom;
  final Color arrowColor;
  final double progress;

  const AnchoredPopoverLayout(
      {super.key, required this.anchor, required this.avoidBottom, required this.arrowColor, required this.progress, super.child});

  @override
  RenderAnchoredPopover createRenderObject(BuildContext context) =>
      RenderAnchoredPopover(anchor, avoidBottom, arrowColor, progress);

  @override
  void updateRenderObject(BuildContext context, RenderAnchoredPopover renderObject) => renderObject
    ..anchor = anchor
    ..avoidBottom = avoidBottom
    ..arrowColor = arrowColor
    ..progress = progress;
}

class RenderAnchoredPopover extends RenderBox with RenderObjectWithChildMixin<RenderBox> {
  RenderAnchoredPopover(this._anchor, this._avoidBottom, this._arrowColor, this._progress);

  static const double side = 12, gap = 12, arrow = 14;

  Rect _anchor;
  set anchor(Rect v) {
    if (v == _anchor) return;
    _anchor = v;
    markNeedsLayout();
  }

  double _avoidBottom;
  set avoidBottom(double v) {
    if (v == _avoidBottom) return;
    _avoidBottom = v;
    markNeedsLayout();
  }

  Color _arrowColor;
  set arrowColor(Color v) {
    if (v == _arrowColor) return;
    _arrowColor = v;
    markNeedsPaint();
  }

  double _progress;
  double get progress => _progress;
  set progress(double v) {
    if (v == _progress) return;
    _progress = v;
    markNeedsPaint();
  }

  /// Whether the body sits below its anchor (else above).
  bool below = true;

  /// The arrow's centre, along the width.
  double arrowCenterX = 0;

  Offset _bodyOffset = Offset.zero;

  @override
  void performLayout() {
    size = constraints.biggest;
    final child = this.child;
    if (child == null) return;
    child.layout(BoxConstraints.tightFor(width: math.max(0, size.width - 2 * side)).copyWith(maxHeight: size.height),
        parentUsesSize: true);
    final h = child.size.height;
    final fitsBelow = _anchor.bottom + gap + h <= size.height - _avoidBottom;
    final fitsAbove = _anchor.top - gap - h >= 0;
    below = fitsBelow || (!fitsAbove && size.height - _anchor.bottom >= _anchor.top);
    final top = below ? _anchor.bottom + gap : _anchor.top - gap - h;
    _bodyOffset = Offset(side, top.clamp(0.0, math.max(0.0, size.height - h)));
    final reach = 18.0; // keep the arrow clear of the 18 px corners
    arrowCenterX = _anchor.center.dx.clamp(side + reach, math.max(side + reach, size.width - side - reach)).toDouble();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || _progress <= 0) return;
    // Grow from the arrow's tip: 96 % → 100 % and 6 px toward it → in place.
    final tip = Offset(arrowCenterX, below ? _bodyOffset.dy - arrow / 2 : _bodyOffset.dy + child.size.height + arrow / 2);
    final scale = 0.96 + 0.04 * _progress;
    final shift = (1 - _progress) * (below ? -6.0 : 6.0);
    final transform = Matrix4.identity()
      ..translateByDouble(offset.dx + tip.dx, offset.dy + tip.dy + shift, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-(offset.dx + tip.dx), -(offset.dy + tip.dy), 0, 1);
    context.pushOpacity(offset, (_progress * 255).round(), (context, offset) {
      context.pushTransform(needsCompositing, Offset.zero, transform, (context, _) {
        context.paintChild(child, offset + _bodyOffset);
        final y = below ? _bodyOffset.dy : _bodyOffset.dy + child.size.height;
        final square = RRect.fromRectAndRadius(
            Rect.fromCenter(center: offset + Offset(arrowCenterX, y), width: arrow, height: arrow), const Radius.circular(3));
        final canvas = context.canvas
          ..save()
          ..translate(offset.dx + arrowCenterX, offset.dy + y)
          ..rotate(math.pi / 4)
          ..translate(-(offset.dx + arrowCenterX), -(offset.dy + y));
        canvas.drawRRect(square, Paint()..color = _arrowColor);
        canvas.restore();
      });
    });
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: _bodyOffset,
      position: position,
      hitTest: (result, transformed) => child.size.contains(transformed) && child.hitTest(result, position: transformed),
    );
  }

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) => transform.translateByDouble(_bodyOffset.dx, _bodyOffset.dy, 0, 1);
}

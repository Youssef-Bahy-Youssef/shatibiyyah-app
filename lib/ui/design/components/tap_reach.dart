// lib/ui/design/components/tap_reach.dart — a tap target wider than what is
// drawn (handoff rule 6: «keep the drawing and give it a 48 dp hit area»).
//
// The child is the whole target. It is laid out [reach] narrower on each side,
// so its neighbours stand where the design draws them, and it still answers taps
// (and reports its full size to assistive technology) across the part that
// overhangs.
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class TapReach extends SingleChildRenderObjectWidget {
  /// How far the target overhangs its place in the layout, on each side.
  final double reach;
  const TapReach({super.key, required this.reach, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTapReach(reach);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) =>
      (renderObject as _RenderTapReach).reach = reach;
}

class _RenderTapReach extends RenderShiftedBox {
  _RenderTapReach(this._reach) : super(null);

  double _reach;
  set reach(double value) {
    if (value == _reach) return;
    _reach = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicWidth(double height) => super.computeMinIntrinsicWidth(height) - 2 * _reach;
  @override
  double computeMaxIntrinsicWidth(double height) => super.computeMaxIntrinsicWidth(height) - 2 * _reach;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final c = child?.getDryLayout(constraints.loosen()) ?? Size.zero;
    return constraints.constrain(Size(c.width - 2 * _reach, c.height));
  }

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    c.layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.constrain(Size(c.size.width - 2 * _reach, c.size.height));
    (c.parentData! as BoxParentData).offset = Offset((size.width - c.size.width) / 2, 0);
  }

  // The overhang is part of the target.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null) return false;
    final at = (c.parentData! as BoxParentData).offset;
    if (!(at & c.size).contains(position)) return false;
    if (hitTestChildren(result, position: position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}

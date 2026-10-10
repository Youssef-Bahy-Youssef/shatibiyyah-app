// lib/ui/design/components/tz_sheet.dart — sheets (item 3.3; v2.css .psheet and
// .picker): a grab and rounded top corners. The full sheet (the player) is the
// surface with 28 px corners; the picker (speed, repetition) is raised with 24 px
// corners and its own padding. Both rise in 320 ms (emphasized) from 60 px down at
// 40 % opacity, instantly under reduced motion.
import 'package:flutter/material.dart';

import '../tokens.g.dart';
import '../tz_theme.dart';
import 'tz_motion.dart';

/// The status bar's height. A modal sheet's own MediaQuery has it removed, so it
/// is read from the view.
double statusBarHeight(BuildContext context) => MediaQueryData.fromView(View.of(context)).padding.top;

class TzSheet extends StatefulWidget {
  final Widget child;
  final bool _picker;

  const TzSheet({super.key, required this.child}) : _picker = false;
  const TzSheet.picker({super.key, required this.child}) : _picker = true;

  static const surfaceKey = ValueKey('tz-sheet-surface');
  static const grabKey = ValueKey('tz-sheet-grab');
  static const riseKey = ValueKey('tz-sheet-rise');

  @override
  State<TzSheet> createState() => _TzSheetState();
}

class _TzSheetState extends State<TzSheet> with SingleTickerProviderStateMixin {
  AnimationController? _rise;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rise ??= AnimationController(vsync: this, duration: tzDuration(context, TzMotion.long))..forward();
  }

  @override
  void dispose() {
    _rise?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final picker = widget._picker;
    final rise = CurvedAnimation(parent: _rise!, curve: TzMotion.emphasized);
    return FadeTransition(
      key: TzSheet.riseKey,
      opacity: Tween(begin: 0.4, end: 1.0).animate(rise),
      child: AnimatedBuilder(
        animation: rise,
        builder: (context, child) => Transform.translate(offset: Offset(0, 60 * (1 - rise.value)), child: child),
        child: Container(
          key: TzSheet.surfaceKey,
          width: double.infinity,
          padding: picker ? const EdgeInsets.fromLTRB(16, 8, 16, 34) : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: picker ? c.raised : c.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(picker ? 24 : TzRadius.sheet)),
            boxShadow: c.float,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: Container(
                    key: TzSheet.grabKey,
                    width: 38,
                    height: 5,
                    decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(3)),
                  ),
                ),
              ),
              if (picker)
                // As tall as its content, and no taller than the room it has: content
                // that scrolls (larger system text) stays inside the sheet.
                Flexible(child: Align(alignment: AlignmentDirectional.centerStart, heightFactor: 1, child: widget.child))
              else
                // The full sheet fills what it is given; its content scrolls inside.
                Flexible(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}

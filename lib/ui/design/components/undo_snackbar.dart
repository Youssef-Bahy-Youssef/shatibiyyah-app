// lib/ui/design/components/undo_snackbar.dart — undo after a delete (item 3.3,
// ADR 0009; v2.css .snack): the message and «تراجع» on the snackbar fill, 52 px
// high, 14 px radius, the float shadow, padded 8 px at the start and 16 px at the
// end as the prototype. Announced as a status. Rises in 320 ms (emphasized) from
// 60 px down at 40 % opacity, instantly under reduced motion.
import 'package:flutter/material.dart';

import '../tokens.g.dart';
import '../tz_theme.dart';
import 'tz_motion.dart';

class UndoSnackbar extends StatefulWidget {
  final String message;
  final String actionLabel;
  final VoidCallback onUndo;

  const UndoSnackbar({super.key, required this.message, this.actionLabel = 'تراجع', required this.onUndo});

  static const surfaceKey = ValueKey('undo-snackbar');
  static const riseKey = ValueKey('undo-snackbar-rise');

  @override
  State<UndoSnackbar> createState() => _UndoSnackbarState();
}

class _UndoSnackbarState extends State<UndoSnackbar> with SingleTickerProviderStateMixin {
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
    final rise = CurvedAnimation(parent: _rise!, curve: TzMotion.emphasized);
    return FadeTransition(
      key: UndoSnackbar.riseKey,
      opacity: Tween(begin: 0.4, end: 1.0).animate(rise),
      child: AnimatedBuilder(
        animation: rise,
        builder: (context, child) => Transform.translate(offset: Offset(0, 60 * (1 - rise.value)), child: child),
        child: Container(
          key: UndoSnackbar.surfaceKey,
          height: 52,
          padding: const EdgeInsetsDirectional.only(start: 8, end: 16),
          decoration: BoxDecoration(color: c.snack, borderRadius: BorderRadius.circular(TzRadius.control), boxShadow: c.float),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(widget.message,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TzType.body.copyWith(fontSize: 14, color: c.onSnack)),
                ),
              ),
              TextButton(
                onPressed: widget.onUndo,
                style: TextButton.styleFrom(
                  minimumSize: const Size(TzSize.touchTarget, TzSize.touchTarget),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: c.snackAct,
                ),
                child: Text(widget.actionLabel,
                    style: TzType.label.copyWith(fontWeight: FontWeight.w700, color: c.snackAct)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

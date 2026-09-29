// lib/ui/widgets/sheet_scaffold.dart — the shared bottom-sheet chrome used by the picker /
// settings sheets (.sheet-backdrop + .sheet). Slide-up 340ms, blurred backdrop, drag handle
// with drag-to-dismiss (>80px). Ported from style.css .sheet/.sheet-backdrop + app.js drag.
import 'dart:ui';
import 'package:flutter/material.dart';

import '../../theme.dart';

class SheetScaffold extends StatefulWidget {
  final bool open;
  final VoidCallback onClose;
  final String? title;
  final Widget child;
  const SheetScaffold({
    super.key,
    required this.open,
    required this.onClose,
    required this.child,
    this.title,
  });

  @override
  State<SheetScaffold> createState() => _SheetScaffoldState();
}

class _SheetScaffoldState extends State<SheetScaffold> {
  double _dragY = 0;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return IgnorePointer(
      ignoring: !widget.open,
      child: Stack(
        children: [
          // backdrop (.sheet-backdrop)
          GestureDetector(
            onTap: widget.onClose,
            child: AnimatedOpacity(
              opacity: widget.open ? 1 : 0,
              duration: const Duration(milliseconds: 280),
              curve: const Cubic(.22, .61, .36, 1),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                child: Container(color: const Color(0x8C120C04)),
              ),
            ),
          ),
          // sheet
          AnimatedPositioned(
            duration: const Duration(milliseconds: 340),
            curve: const Cubic(.22, .61, .36, 1),
            left: 0,
            right: 0,
            bottom: widget.open ? 0 : -800,
            child: Transform.translate(
              offset: Offset(0, _dragY),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF2E2110), Color(0xFF1F1609)],
                      ),
                      border: Border(top: BorderSide(color: C.goldDeep)),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    padding: EdgeInsets.fromLTRB(
                        18, 10, 18, mq.padding.bottom + 22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // drag handle (.sheet-handle)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragUpdate: (d) =>
                              setState(() => _dragY = (_dragY + d.delta.dy).clamp(0, 800)),
                          onVerticalDragEnd: (_) {
                            if (_dragY > 80) {
                              widget.onClose();
                            }
                            setState(() => _dragY = 0);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 26),
                            child: Container(
                              width: 42,
                              height: 5,
                              decoration: BoxDecoration(
                                color: C.line,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (widget.title != null) ...[
                          Text(widget.title!,
                              textAlign: TextAlign.center,
                              style: kufi(
                                  size: 18.4,
                                  weight: 600,
                                  color: C.goldBright)),
                          const SizedBox(height: 16),
                        ],
                        widget.child,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// lib/ui/reader/split_panel.dart — the tablet split (plan P8, features-v3
// commentary-split-screen; design board 1t).
//
// From 600 dp wide, «الشرح» opens the commentary beside the page instead of over it:
// the page keeps the start side, a divider (30–70 %, kept per orientation) and the
// panel the other. The panel's header: «شرح البيت N» and the chapter, «يتبع التلاوة»
// (the playing or selected verse moves it, unless the student is scrolling in it),
// «قارن الشروح», «حجم الخط», close.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/settings_store.dart';
import '../design/tokens.g.dart';
import '../../utils/arabic.dart';
import '../commentary/commentary_screen.dart';
import '../commentary/compare_screen.dart';
import '../design/taysir_colors.dart';
import 'reader_controller.dart';

/// The width from which the reader splits (the tablet breakpoint).
const double kSplitMinWidth = 600;

/// The divider's width between the page and the panel.
const double kSplitDividerWidth = 16;

/// Below this panel width its header takes two rows.
const double _twoRowsBelow = 460;

class SplitPanel extends StatefulWidget {
  final ReaderController reader;
  const SplitPanel({super.key, required this.reader});

  @override
  State<SplitPanel> createState() => _SplitPanelState();
}

class _SplitPanelState extends State<SplitPanel> {
  ReaderController get r => widget.reader;
  late int _shown = r.splitVerse; // the first verse of the passage on show
  bool _navigating = false;
  late double _scale = r.store?.splitTextScale ?? 1;

  void _nextScale() {
    setState(() => _scale = cycle(kSplitTextScales, _scale));
    r.store?.splitTextScale = _scale;
  }

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final chapter = r.content.matn.chapterOfVerse(_shown);
    return Material(
      color: t.bg,
      child: SafeArea(
        bottom: false,
        left: false,
        right: false,
        child: Column(
          children: [
            // One row when the panel is wide; below [_twoRowsBelow] the controls
            // go under the title so a narrow panel (the divider at 70 %) still fits.
            LayoutBuilder(
              builder: (context, box) {
                final title = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'شرح البيت ${ar(_shown)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TzType.title.copyWith(color: t.text),
                    ),
                    Text(
                      chapter.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TzType.chapter.copyWith(color: t.muted),
                    ),
                  ],
                );
                // «يتبع التلاوة»: one item for a screen reader, the label with its switch.
                // [shrink]: the label may be cut short (inside a bounded, narrow row).
                Widget follow({bool shrink = false}) {
                  final label = Text(
                    'يتبع التلاوة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TzType.label.copyWith(color: t.dim),
                  );
                  return MergeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (shrink) Flexible(child: label) else label,
                        Switch(
                          value: r.splitFollow,
                          onChanged: r.setSplitFollow,
                          activeThumbColor: t.onGold,
                          activeTrackColor: t.gold,
                        ),
                      ],
                    ),
                  );
                }

                final compare = IconButton(
                  tooltip: 'قارن الشروح',
                  icon: Icon(LucideIcons.columns3, size: 20, color: t.text),
                  onPressed: () => CompareScreen.open(context, r.content, _shown),
                );
                final size = IconButton(
                  tooltip: 'حجم الخط',
                  icon: Icon(LucideIcons.aLargeSmall, size: 20, color: t.text),
                  onPressed: _nextScale,
                );
                final close = IconButton(
                  tooltip: 'إغلاق التقسيم',
                  icon: Icon(LucideIcons.x, size: 20, color: t.text),
                  onPressed: r.closeSplit,
                );
                return Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 4, 4),
                  child: box.maxWidth >= _twoRowsBelow
                      ? Row(
                          children: [
                            Expanded(child: title),
                            follow(),
                            compare,
                            size,
                            close,
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(child: title),
                                close,
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(child: follow(shrink: true)),
                                Row(mainAxisSize: MainAxisSize.min, children: [compare, size]),
                              ],
                            ),
                          ],
                        ),
                );
              },
            ),
            Expanded(
              child: CommentaryPane(
                content: r.content,
                verse: r.splitVerse,
                textScale: _scale,
                onNavigate: () => _navigating = true,
                onShown: (block) {
                  final from = block.fromVerse;
                  if (from == null) return;
                  setState(() => _shown = from);
                  if (_navigating) {
                    _navigating = false;
                    r.pinSplit(from); // the student's own move: the panel stays there
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The draggable line between the page and the panel. [fraction] is the page's
/// share of [total]; dragging reports the new share (clamped to 30–70 %), and
/// [onEnd] when the drag is over, to keep it.
class SplitDivider extends StatelessWidget {
  final double fraction;
  final double total;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;
  const SplitDivider({
    super.key,
    required this.fraction,
    required this.total,
    required this.onChanged,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    double clamp(double v) => v.clamp(kSplitMin, kSplitMax).toDouble();
    return Semantics(
      slider: true,
      label: 'الفاصل بين الصفحة والشرح',
      value: '${ar((fraction * 100).round())}٪',
      increasedValue: '${ar((clamp(fraction + 0.05) * 100).round())}٪',
      decreasedValue: '${ar((clamp(fraction - 0.05) * 100).round())}٪',
      onIncrease: () {
        onChanged(clamp(fraction + 0.05));
        onEnd();
      },
      onDecrease: () {
        onChanged(clamp(fraction - 0.05));
        onEnd();
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Right to left: the page is on the right, so dragging left widens it.
          onHorizontalDragUpdate: (d) => onChanged(clamp(fraction - d.delta.dx / total)),
          onHorizontalDragEnd: (_) => onEnd(),
          child: SizedBox(
            width: kSplitDividerWidth,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(width: 1, color: t.line),
                Container(
                  width: 6,
                  height: 44,
                  decoration: BoxDecoration(color: t.muted, borderRadius: BorderRadius.circular(999)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

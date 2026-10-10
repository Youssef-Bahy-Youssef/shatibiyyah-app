// lib/ui/reader/reader_screen.dart — the reader: the page and the top bar.
//
// features-v3: fixed-page-layout, immersive-mode, page-header-info,
// detach-resume-chip. The page sits in a rectangle computed once (ReaderLayout)
// between the top bar's zone and the dock's; the top bar fades over its zone
// (show 180 ms cubic(.2,0,0,1) with −6 px of travel, hide 150 ms cubic(.4,0,1,1),
// reduced motion: opacity only in 100 ms), so nothing ever moves or covers the
// page. The dock itself, with now playing and the tabs, is the shell's
// (lib/ui/shell/app_shell.dart, item 3.4); the selection bar takes its zone.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/tokens.g.dart';
import '../../utils/arabic.dart';
import '../../data/matn_repository.dart';
import '../../data/settings_store.dart' show kSplitDefault;
import '../commentary/commentary_screen.dart';
import '../design/taysir_colors.dart';
import '../search/search_screen.dart';
import '../share/share_sheet.dart';
import '../study/study_sheets.dart';
import '../widgets/page_viewer.dart';
import '../widgets/verse_menu.dart';
import 'fixed_page_layout.dart';
import 'listen_sheet.dart';
import 'reader_controller.dart';
import 'split_panel.dart';
import 'shamsa.dart';
import 'text_reader.dart';
import 'tools_sheet.dart';

const _showCurve = Cubic(.2, 0, 0, 1);
const _hideCurve = Cubic(.4, 0, 1, 1);

class ReaderScreen extends StatefulWidget {
  final ReaderController reader;
  final VoidCallback? onSearch;
  final VoidCallback? onTools;

  const ReaderScreen({super.key, required this.reader, this.onSearch, this.onTools});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _text = GlobalKey<TextReaderState>();

  ReaderController get reader => widget.reader;

  /// Where the verse menu points: the verse's row in text mode, its box on the page otherwise.
  Rect? _anchor(int verse, ReaderLayout layout) => reader.textMode
      ? _text.currentState?.rowRect(verse)
      : reader.viewer.viewRectOfVerse(verse)?.shift(layout.page.topLeft);

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: t.bg,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.4),
              radius: 1.2,
              colors: [t.panel, t.bg],
              stops: const [0, 0.7],
            ),
          ),
          child: AnimatedBuilder(
            animation: reader,
            // Every child is positioned, so without `expand` the stack is 0×0 and clips them all.
            // Back closes the verse menu, then the selection, before it leaves the reader
            // (neither is a route).
            builder: (context, _) => PopScope(
              canPop: reader.menuVerse == null &&
                  reader.headingChapter == null &&
                  !reader.selecting &&
                  !_splitOn(context),
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                if (reader.menuVerse != null) {
                  reader.closeMenu();
                } else if (_splitOn(context)) {
                  reader.closeSplit();
                } else if (reader.headingChapter != null) {
                  reader.closeHeading();
                } else {
                  reader.clearSelection();
                }
              },
              child: LayoutBuilder(builder: _body),
            ),
          ),
        ),
      ),
    );
  }

  /// Whether the split is on screen: open, and the window wide enough (a phone, or a
  /// tablet made narrow, keeps it closed without forgetting it).
  bool _splitShown = false;

  /// The split as Back sees it: decided from the screen width, which is known before
  /// the layout below runs ([_splitShown] is set there, a frame later).
  bool _splitOn(BuildContext context) =>
      widget.reader.splitOpen && MediaQuery.sizeOf(context).width >= kSplitMinWidth;
  bool _wide = false; // the tablet breakpoint: «الشرح» opens the split
  double? _dragFraction; // while the divider is dragged

  /// The reader alone, or (a tablet with the split open) the reader beside the
  /// commentary panel. The reader half gets its own MediaQuery size, so the page,
  /// the bars and the verse menu lay themselves out inside it.
  Widget _body(BuildContext context, BoxConstraints box) {
    final reader = widget.reader;
    _wide = box.maxWidth >= kSplitMinWidth;
    _splitShown = reader.splitOpen && _wide;
    if (!_splitShown) return _stack(context);
    final mq = MediaQuery.of(context);
    final landscape = box.maxWidth > box.maxHeight;
    final fraction = _dragFraction ?? reader.store?.splitFraction(landscape: landscape) ?? kSplitDefault;
    final total = box.maxWidth - kSplitDividerWidth;
    final readerWidth = total * fraction;
    return Row(
      children: [
        SizedBox(
          width: readerWidth,
          child: MediaQuery(
            data: mq.copyWith(size: Size(readerWidth, box.maxHeight)),
            child: Builder(builder: _stack),
          ),
        ),
        SplitDivider(
          fraction: fraction,
          total: total,
          onChanged: (f) => setState(() => _dragFraction = f),
          onEnd: () {
            final f = _dragFraction;
            if (f != null) reader.store?.setSplitFraction(f, landscape: landscape);
            setState(() => _dragFraction = null);
          },
        ),
        Expanded(child: SplitPanel(reader: reader)),
      ],
    );
  }

  /// The reader: the page (or text mode), the bars, the menu and the cards.
  Widget _stack(BuildContext context) {
    final reader = widget.reader;
    final t = TaysirColors.of(context);
    final mq = MediaQuery.of(context);
    final layout = ReaderLayout.compute(mq.size, mq.padding);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fromRect(
          rect: layout.page,
          // Kept mounted in text mode so the page is where it was when the student returns.
          child: Offstage(
            offstage: reader.textMode,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: PageViewer(
                controller: reader.viewer,
                verseLabel: (n) {
                  final v = reader.content.matn.verse(n);
                  return 'البيت ${ar(n)}: ${v.firstHemistich}، ${v.secondHemistich}';
                },
              ),
            ),
          ),
        ),
        if (reader.textMode)
          Positioned.fromRect(
            rect: layout.textZone,
            child: TextReader(key: _text, reader: reader),
          ),
        if (!reader.chromeVisible && !reader.textMode)
          Positioned(
            left: 0,
            right: 0,
            bottom: mq.padding.bottom + 12,
            child: IgnorePointer(
              child: Center(
                child: Text(ar(reader.page),
                    style: TzType.caption.copyWith(color: t.muted.withValues(alpha: 0.7))),
              ),
            ),
          ),
        _Chrome(
          rect: layout.bar,
          visible: reader.chromeVisible,
          travel: -6,
          child: reader.selecting
              ? _SelectionHeader(reader: reader)
              : _TopBar(
                  reader: reader,
                  onSearch: widget.onSearch ?? () => SearchScreen.open(context, reader),
                  onTools: widget.onTools ?? () => showToolsSheet(context, reader),
                ),
        ),
        // While selecting, the selection bar takes the dock's zone.
        if (reader.selecting)
          _Chrome(
            rect: layout.dock,
            visible: reader.selectionComplete,
            travel: 8,
            child: _SelectionActions(reader: reader),
          ),
        if (reader.selecting && !reader.selectionComplete)
          Positioned(
            left: 0,
            right: 0,
            top: layout.bar.bottom + 8,
            child: IgnorePointer(child: Center(child: _SelectionHint(reader: reader))),
          ),
        if (reader.detached && reader.playing && !reader.selecting)
          Positioned(
            left: 0,
            right: 0,
            top: layout.dock.top - 24,
            child: Center(child: _ResumeChip(reader: reader)),
          ),
        if (reader.headingChapter != null) ...[
          Positioned.fill(
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: reader.closeHeading),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: layout.bar.bottom + 10,
            child: _HeadingCard(
              reader: reader,
              chapter: reader.headingChapter!,
              onExplain: _wide ? reader.openSplit : null,
            ),
          ),
        ],
        if (reader.notice != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: mq.size.height - layout.dock.top + 16,
            child: IgnorePointer(child: Center(child: _Notice(text: reader.notice!))),
          ),
        VerseMenu(
          listenable: reader,
          content: reader.content,
          verse: () => reader.menuVerse,
          anchor: (v) => _anchor(v, layout),
          onClose: reader.closeMenu,
          canPlay: () => reader.audioAvailable,
          onPlayFrom: (v) => showListenSheet(context, reader, v),
          onStartRange: reader.startSelection,
          onShare: (v) => showShareSheet(context, reader.content, v),
          onBookmark: reader.personal == null
              ? null
              : (v) => showBookmarkSheet(context,
                  personal: reader.personal!, content: reader.content, from: v, onDone: reader.showNotice),
          onNote: reader.personal == null
              ? null
              : (v) => showNoteSheet(context,
                  personal: reader.personal!, content: reader.content, verse: v, onDone: reader.showNotice),
          // Any bookmark covering the verse, a run included (F-51).
          bookmarked: (v) => reader.personal?.bookmarksCovering(v).isNotEmpty ?? false,
          hasNote: (v) => reader.personal?.noteFor(v) != null,
          onExplain: _wide ? reader.openSplit : null,
        ),
      ],
    );
  }
}

/// The card of a chapter heading tapped on the page: its title, where it is, and
/// «تشغيل الباب» (with a recording) · «الشرح» (the commentary from its first verse).
class _HeadingCard extends StatelessWidget {
  final ReaderController reader;
  final MatnChapter chapter;
  final void Function(int verse)? onExplain; // the tablet's split; else the commentary screen
  const _HeadingCard({required this.reader, required this.chapter, this.onExplain});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final intro = chapter.orderIndex == 0;
    final range = 'الأبيات ${isolatedRange(chapter.fromVerse, chapter.toVerse)}';
    final page = reader.content.layout.pageOfVerse(chapter.fromVerse);
    final meta = intro
        ? '${chapter.shortLabel}، $range'
        : 'الباب ${ar(chapter.orderIndex)}، $range، ص ${ar(page)}';
    return Material(
      color: t.panel,
      elevation: 12,
      shadowColor: t.float.first.color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: t.line)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(intro ? chapter.shortLabel : chapter.title,
                style: TzType.chapter.copyWith(color: t.text)),
            Text(meta, style: TzType.caption.copyWith(color: t.muted)),
            const SizedBox(height: 10),
            Row(
              children: [
                if (reader.audioAvailable) ...[
                  Expanded(
                    child: FilledButton(
                      onPressed: () => reader.playChapter(chapter),
                      style: FilledButton.styleFrom(
                        backgroundColor: t.gold,
                        foregroundColor: t.onGold,
                        minimumSize: const Size.fromHeight(48),
                        shape: const StadiumBorder(),
                      ),
                      child: Text('تشغيل الباب', style: TzType.body.copyWith(color: t.onGold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                OutlinedButton.icon(
                  onPressed: () {
                    reader.closeHeading();
                    if (onExplain case final open?) {
                      open(chapter.fromVerse);
                    } else {
                      CommentaryScreen.open(context, reader.content, chapter.fromVerse);
                    }
                  },
                  icon: Icon(LucideIcons.bookOpen, size: 17, color: t.goldText),
                  label: Text('الشرح', style: TzType.label.copyWith(color: t.text)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    side: BorderSide(color: t.line),
                    shape: const StadiumBorder(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A short notice (the prototype's toast), e.g. «بدأ باب جديد · …».
class _Notice extends StatelessWidget {
  final String text;
  const _Notice({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: t.panel2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.line),
          boxShadow: t.float,
        ),
        child: Text(text, textAlign: TextAlign.center, style: TzType.label.copyWith(color: t.text)),
      ),
    );
  }
}

/// The top bar while selecting: clear, the count and range, and «الباب كاملًا».
class _SelectionHeader extends StatelessWidget {
  final ReaderController reader;
  const _SelectionHeader({required this.reader});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final sel = reader.selection!;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.line),
        boxShadow: t.float,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'إلغاء التحديد',
            onPressed: reader.clearSelection,
            icon: Icon(LucideIcons.x, size: 22, color: t.text),
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(selectedVersesCount(sel.to - sel.from + 1),
                    maxLines: 1, style: TzType.head.copyWith(color: t.goldText)),
                Text(
                  sel.from == sel.to
                      ? 'البيت ${ar(sel.from)}'
                      : 'الأبيات ${ar(sel.from)}–${ar(sel.to)} · اضغط بيتًا آخر للتمديد',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TzType.caption.copyWith(color: t.muted),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: OutlinedButton(
              onPressed: reader.selectChapter,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                side: BorderSide(color: t.line, width: 1.5),
                shape: const StadiumBorder(),
              ),
              child: Text('الباب كاملًا', style: TzType.label.copyWith(color: t.text)),
            ),
          ),
        ],
      ),
    );
  }
}

/// «المس البيت الأخير لتحديد نطاق يبدأ من N», until the second verse is tapped.
class _SelectionHint extends StatelessWidget {
  final ReaderController reader;
  const _SelectionHint({required this.reader});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.panel2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.line),
      ),
      child: Text('المس البيت الأخير لتحديد نطاق يبدأ من ${ar(reader.selection!.from)}',
          style: TzType.caption.copyWith(color: t.goldBright)),
    );
  }
}

/// The selection bar over the player's zone: تشغيل (with a recording) · نسخ · مرجع · إلغاء.
class _SelectionActions extends StatelessWidget {
  final ReaderController reader;
  const _SelectionActions({required this.reader});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final sel = reader.selection;
    void copy() {
      if (sel == null) return;
      Clipboard.setData(ClipboardData(text: rangeCopyText(reader.content, sel.from, sel.to)));
      reader.clearSelection();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(
          sel.from == sel.to ? 'نُسخ البيت ${ar(sel.from)}' : 'نُسخت الأبيات ${ar(sel.from)}–${ar(sel.to)}',
          style: TzType.label.copyWith(color: t.text),
        ),
        backgroundColor: t.raised,
        duration: const Duration(seconds: 2),
      ));
    }

    Widget action(IconData icon, String label, VoidCallback onTap, {bool primary = false}) => Expanded(
          child: Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primary ? t.gold : t.panel2,
                      border: primary ? null : Border.all(color: t.line),
                    ),
                    child: Icon(icon, size: 22, color: primary ? t.onGold : t.goldText),
                  ),
                  const SizedBox(height: 6),
                  Text(label, style: TzType.caption.copyWith(color: t.text)),
                ],
              ),
            ),
          ),
        );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.line),
        boxShadow: t.float,
      ),
      child: Row(
        children: [
          if (reader.audioAvailable) action(LucideIcons.play, 'تشغيل', reader.playSelection, primary: true),
          action(LucideIcons.copy, 'نسخ', copy),
          if (reader.personal != null && sel != null)
            action(LucideIcons.bookmarkPlus, 'مرجع', () {
              reader.clearSelection();
              showBookmarkSheet(context,
                  personal: reader.personal!,
                  content: reader.content,
                  from: sel.from,
                  to: sel.to == sel.from ? null : sel.to,
                  onDone: reader.showNotice);
            }),
          action(LucideIcons.x, 'إلغاء', reader.clearSelection),
        ],
      ),
    );
  }
}

/// A chrome element over its reserved zone: fades and slides a few pixels, never moves the page.
class _Chrome extends StatelessWidget {
  final Rect rect;
  final bool visible;
  final double travel;
  final Widget child;
  const _Chrome({required this.rect, required this.visible, required this.travel, required this.child});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final duration = Duration(milliseconds: reduce ? 100 : (visible ? 180 : 150));
    final curve = visible ? _showCurve : _hideCurve;
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: duration,
          curve: curve,
          child: AnimatedSlide(
            offset: Offset(0, visible || reduce ? 0 : travel / rect.height),
            duration: duration,
            curve: curve,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final ReaderController reader;
  final VoidCallback? onSearch, onTools;
  const _TopBar({required this.reader, this.onSearch, this.onTools});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final chapter = reader.headerChapter;
    final part = reader.content.matn.partOf(chapter);
    final pages = reader.content.layout.pageCount;
    Widget icon(IconData i, String label, VoidCallback? onTap) => IconButton(
          tooltip: label,
          onPressed: onTap,
          icon: Icon(i, size: 21, color: t.text),
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.line),
        boxShadow: t.float,
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 24,
                  child: Text(chapter.shortLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TzType.chapter.copyWith(color: t.text)),
                ),
                SizedBox(
                  height: 15,
                  child: Text(reader.textMode ? 'العرض النصي' : '${part.title} · ص ${ar(reader.page)} من ${ar(pages)}',
                      maxLines: 1, style: TzType.caption.copyWith(color: t.muted)),
                ),
              ],
            ),
          ),
          icon(LucideIcons.search, 'بحث وانتقال', onSearch),
          icon(LucideIcons.slidersHorizontal, 'أدوات العرض والصوت', onTools),
        ],
      ),
    );
  }
}

class _ResumeChip extends StatelessWidget {
  final ReaderController reader;
  const _ResumeChip({required this.reader});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return GestureDetector(
      onTap: reader.resumeFollowing,
      child: Container(
        height: 48,
        padding: const EdgeInsetsDirectional.only(start: 8, end: 18),
        decoration: BoxDecoration(
          color: t.gold,
          borderRadius: BorderRadius.circular(999),
          boxShadow: t.float,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Shamsa(size: 32, verse: reader.verse, playing: true),
          const SizedBox(width: 8),
          Text('عودة إلى البيت ${ar(reader.verse)}', style: TzType.body.copyWith(color: t.onGold)),
        ]),
      ),
    );
  }
}

// lib/ui/reader/reader_screen.dart — the v3 reader: the page, the top bar and the player.
//
// features-v3: fixed-page-layout, immersive-mode, page-header-info, mini-bar,
// now-playing-medallion, detach-resume-chip. The page sits in a rectangle computed
// once (ReaderLayout); the bar and the player fade over their reserved zones
// (show 180 ms cubic(.2,0,0,1) with −6 / +8 px of travel, hide 150 ms
// cubic(.4,0,1,1), reduced motion: opacity only in 100 ms), so nothing ever moves
// or covers the page.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme.dart' show kufi, naskh;
import '../../utils/arabic.dart';
import '../../data/matn_repository.dart';
import '../../data/settings_store.dart' show kSplitDefault;
import '../commentary/commentary_screen.dart';
import '../design/taysir_colors.dart';
import '../search/search_screen.dart';
import '../share/share_sheet.dart';
import '../shell/app_drawer.dart';
import '../shell/downloads_screen.dart';
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
  final VoidCallback? onMenu;
  final VoidCallback? onSearch;
  final VoidCallback? onTools;

  const ReaderScreen({super.key, required this.reader, this.onMenu, this.onSearch, this.onTools});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _text = GlobalKey<TextReaderState>();
  final _scaffold = GlobalKey<ScaffoldState>();

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
        key: _scaffold,
        backgroundColor: t.bg,
        drawer: AppDrawer(reader: reader),
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
                    style: naskh(size: 13, color: t.muted.withValues(alpha: 0.7))),
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
                  onMenu: widget.onMenu ?? () => _scaffold.currentState?.openDrawer(),
                  onSearch: widget.onSearch ?? () => SearchScreen.open(context, reader),
                  onTools: widget.onTools ?? () => showToolsSheet(context, reader),
                ),
        ),
        // While selecting, the player makes way for the selection bar.
        _Chrome(
          rect: layout.player,
          visible: reader.chromeVisible && !reader.selecting,
          travel: 8,
          child: _PlayerBar(
            reader: reader,
            onOpen: () => reader.audioAvailable || reader.library == null
                ? showToolsSheet(context, reader, tab: ToolsTab.audio)
                : DownloadsScreen.open(context, reader.library!),
          ),
        ),
        if (reader.selecting)
          _Chrome(
            rect: layout.player,
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
            top: layout.player.top - 24,
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
            bottom: mq.size.height - layout.player.top + 16,
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
          bookmarked: (v) => reader.personal?.bookmarkAt(v) != null,
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
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: t.line)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(intro ? chapter.shortLabel : chapter.title,
                style: naskh(size: 18, weight: FontWeight.w700, color: t.text, height: 1.7)),
            Text(meta, style: kufi(size: 12.5, weight: 400, color: t.muted)),
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
                      child: Text('تشغيل الباب', style: kufi(size: 15, weight: 600, color: t.onGold)),
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
                  label: Text('الشرح', style: kufi(size: 14.5, weight: 400, color: t.text)),
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
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 10))],
        ),
        child: Text(text, textAlign: TextAlign.center, style: kufi(size: 14, weight: 400, color: t.text)),
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
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 8))],
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
                    maxLines: 1, style: kufi(size: 16, weight: 600, color: t.goldText)),
                Text(
                  sel.from == sel.to
                      ? 'البيت ${ar(sel.from)}'
                      : 'الأبيات ${ar(sel.from)}–${ar(sel.to)} · اضغط بيتًا آخر للتمديد',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: kufi(size: 12, weight: 400, color: t.muted),
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
              child: Text('الباب كاملًا', style: kufi(size: 13, weight: 400, color: t.text)),
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
          style: kufi(size: 12.5, weight: 400, color: t.goldBright)),
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
          style: kufi(size: 14, weight: 500, color: t.text),
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
                  Text(label, style: kufi(size: 12.5, weight: 400, color: t.text)),
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
        boxShadow: const [BoxShadow(color: Color(0x52000000), blurRadius: 30, offset: Offset(0, 10))],
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
  final VoidCallback? onMenu, onSearch, onTools;
  const _TopBar({required this.reader, this.onMenu, this.onSearch, this.onTools});

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
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Row(
        children: [
          icon(LucideIcons.menu, 'القائمة', onMenu),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 24,
                  child: Text(chapter.shortLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: naskh(size: 15.5, weight: FontWeight.w700, color: t.text, height: 1.5)),
                ),
                SizedBox(
                  height: 15,
                  child: Text(reader.textMode ? 'العرض النصي' : '${part.title} · ص ${ar(reader.page)} من ${ar(pages)}',
                      maxLines: 1, style: kufi(size: 11.5, weight: 400, color: t.muted, height: 1.3)),
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

class _PlayerBar extends StatelessWidget {
  final ReaderController reader;
  final VoidCallback? onOpen;
  const _PlayerBar({required this.reader, this.onOpen});

  @override
  Widget build(BuildContext context) {
    // Download progress comes from the library, not the reader.
    final library = reader.library;
    return library == null ? _bar(context) : AnimatedBuilder(animation: library, builder: (context, _) => _bar(context));
  }

  Widget _bar(BuildContext context) {
    final t = TaysirColors.of(context);
    final chapter = reader.chapter;
    final audio = reader.audioAvailable;
    final repeats = reader.settings.verseRepeats;
    final sections = reader.settings.sectionRepeats;
    final library = reader.library;
    final downloading = library?.isDownloading(reader.recording) ?? false;
    final progress = library?.progressOf(reader.recording);
    final String line1, line2;
    if (!audio) {
      line1 = downloading && progress != null
          ? 'تُنزَّل التلاوة ${ar((progress.fraction * 100).floor())}٪'
          : 'التلاوة غير منزّلة بعد';
      line2 = downloading ? reader.recording.reciterName : 'المتن والشروح تعمل دون تنزيل';
    } else if (reader.playing) {
      line1 = reader.inTitle ? chapter.shortLabel : 'البيت ${ar(reader.verse)} من ${ar(chapter.toVerse)}';
      line2 = reader.recording.reciterName;
    } else {
      line1 = 'متوقّف · البيت ${ar(reader.verse)}';
      line2 = reader.recording.reciterName;
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.line),
        boxShadow: const [BoxShadow(color: Color(0x52000000), blurRadius: 30, offset: Offset(0, 10))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 12, 4),
            child: Row(
              children: [
                if (audio)
                  Shamsa(
                    size: 50,
                    verse: reader.verse,
                    playing: reader.playing,
                    chip: (repeats == null || repeats > 1) && reader.playing
                        ? 'البيت ${ar(reader.verseRepetition)}/${repeats == null ? '∞' : ar(repeats)}'
                        : null,
                    ring: (sections == null || sections > 1) ? reader.sectionRepetition / (sections ?? 1) : null,
                  )
                else
                  // The single «تنزيل» button of the no-audio player (features-v3 audio-downloads).
                  Semantics(
                    button: true,
                    label: 'التنزيلات',
                    child: GestureDetector(
                      onTap: onOpen,
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration:
                            BoxDecoration(shape: BoxShape.circle, border: Border.all(color: t.gold, width: 1.5)),
                        child: Icon(LucideIcons.download, size: 22, color: t.goldText),
                      ),
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onOpen,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 50), // as tall as the shamsa beside it
                      child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(line1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: kufi(size: 14, weight: 600, color: t.text)),
                        Text(line2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: kufi(size: 12, weight: 400, color: t.muted)),
                      ],
                    ),
                    ),
                  ),
                ),
                if (audio) _Transport(reader: reader),
              ],
            ),
          ),
          if (audio) _ScopeProgress(reader: reader),
        ],
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  final ReaderController reader;
  const _Transport({required this.reader});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    Widget step(IconData icon, String label, VoidCallback onTap) => IconButton(
          tooltip: label,
          onPressed: onTap,
          icon: Icon(icon, size: 20, color: t.goldText),
          constraints: const BoxConstraints.tightFor(width: 44, height: 48),
        );
    return Directionality(
      textDirection: TextDirection.ltr, // transport and scrubber stay left-to-right
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        step(LucideIcons.skipBack, 'البيت السابق', reader.previous),
        Semantics(
          button: true,
          label: reader.playing ? 'إيقاف مؤقت' : 'تشغيل',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: reader.playPause,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [t.goldBright, t.gold]),
                boxShadow: [BoxShadow(color: t.gold.withValues(alpha: 0.5), blurRadius: 18, offset: const Offset(0, 6))],
              ),
              child: Icon(reader.playing ? LucideIcons.pause : LucideIcons.play, size: 22, color: t.onGold),
            ),
          ),
        ),
        step(LucideIcons.skipForward, 'البيت التالي', reader.next),
      ]),
    );
  }
}

/// Where playback is inside the current chapter (verse-based; exact scrubbing arrives with the tools sheet).
class _ScopeProgress extends StatelessWidget {
  final ReaderController reader;
  const _ScopeProgress({required this.reader});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final c = reader.chapter;
    final fraction = ((reader.verse - c.fromVerse + 0.4) / c.verseCount).clamp(0.0, 1.0);
    return Semantics(
      label: 'موضع التلاوة في الباب',
      value: '${ar(reader.verse - c.fromVerse + 1)} من ${ar(c.verseCount)}',
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(value: fraction, minHeight: 4, color: t.gold, backgroundColor: t.line),
          ),
        ),
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
          boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 10))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Shamsa(size: 32, verse: reader.verse, playing: true),
          const SizedBox(width: 8),
          Text('عودة إلى البيت ${ar(reader.verse)}', style: kufi(size: 15, weight: 600, color: t.onGold)),
        ]),
      ),
    );
  }
}

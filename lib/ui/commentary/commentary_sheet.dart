// lib/ui/commentary/commentary_sheet.dart — «الشرح» as a sheet tied to its verse
// (item 3.9, ADR 0022; handoff commentary-*).
//
// It opens under the chosen verse, a notch pointing at it, over text mode or the
// scanned page: the verse stays outlined behind it. It rests at half height and
// drags (or its button takes it) to full. The matn appears once: behind the
// sheet at half height, in a strip pinned over the text at full height. A block
// that explains several verses lists them as chips.
//
// The header: a tab per book, expand and close, the author's byline and the
// verse, and a reading-progress line. The text: segment headings, justified
// paragraphs at the reader's size, Quranic quotations in lapis ﴿ ﴾, the book's
// quotations of the verse as chips that light the phrase in the strip, footnote
// markers with the notes collected under the text. The binding stepper goes to
// the neighbouring verses and says the place in the chapter.
import 'package:flutter/material.dart';

import '../../data/commentary_repository.dart';
import '../../utils/arabic.dart';
import '../design/components/binding_stepper.dart';
import '../design/components/commentary_inline.dart';
import '../design/components/matn_strip.dart';
import '../design/components/tz_sheet.dart' show statusBarHeight;
import '../design/components/verse_sheet_surface.dart';
import '../design/tokens.g.dart';
import '../design/tz_icon.dart';
import '../design/tz_theme.dart';
import '../reader/reader_controller.dart';
import '../reader/verse_rubrics.dart';
import 'commentary_parts.dart';
import 'commentary_screen.dart' show CommentaryScreen;

class CommentarySheet extends StatefulWidget {
  final ReaderController reader;

  /// The sheet's height at rest, as a share of the space it stands in: the chosen
  /// verse stays in view above it.
  final double half;

  /// Where the chosen verse is across the screen, for the notch.
  final double notchX;

  /// Whether the verse shows above the sheet at rest. When it does not (a verse
  /// low on the page), the sheet carries it in the matn strip at any height.
  final bool verseVisible;

  /// Whether the three kinds of quoted text get their key (at rest, over text mode).
  final bool legend;

  const CommentarySheet(
      {super.key,
      required this.reader,
      required this.half,
      required this.notchX,
      this.verseVisible = true,
      this.legend = false});

  static const surfaceKey = ValueKey('commentary-sheet');
  static const notchKey = ValueKey('commentary-notch');
  static const grabKey = ValueKey('commentary-grab');
  static const progressKey = ValueKey('commentary-progress');
  static const bylineKey = ValueKey('commentary-byline');
  static const rangeKey = ValueKey('commentary-range');

  /// The header's height: the grab, the tabs' line, the byline and the progress line.
  static const double headerExtent = 85;

  @override
  State<CommentarySheet> createState() => _CommentarySheetState();
}

class _CommentarySheetState extends State<CommentarySheet> {
  final _sheet = DraggableScrollableController();
  late String _bookId;
  late int _verse;
  BlockView? _view;
  int? _stripVerse;
  MatnQuoteSpan? _quote;
  bool _full = false;
  double _progress = 0;
  double _fullFraction = 1;
  List<double> _snaps = const [0];

  ReaderController get reader => widget.reader;
  CommentaryRepository get books => reader.content.books;

  @override
  void initState() {
    super.initState();
    final saved = reader.commentaryBook;
    _bookId = books.books.any((b) => b.id == saved) ? saved! : books.defaultBook.id;
    _verse = reader.commentaryVerse!;
    reader.addListener(_onReader);
    _load();
  }

  @override
  void dispose() {
    reader.removeListener(_onReader);
    _sheet.dispose();
    super.dispose();
  }

  void _onReader() {
    final verse = reader.commentaryVerse;
    if (verse == null || verse == _verse) return;
    _verse = verse;
    _load();
  }

  Future<void> _load() async {
    final verse = _verse, book = _bookId;
    final view = await loadBlockView(books, book, verse);
    if (!mounted || verse != _verse || book != _bookId) return;
    setState(() {
      _view = view;
      _stripVerse = null;
      _quote = null;
      _progress = 0;
    });
    // A new passage starts at its top; the line shows the part already in view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scroll = _scroll;
      if (!mounted || scroll == null || !scroll.hasClients) return;
      if (scroll.offset > 0) scroll.jumpTo(0);
      _read(scroll.position);
    });
    CommentaryScreen.onOpened?.call();
  }

  void _chooseBook(String id) {
    if (id == _bookId) return;
    setState(() => _bookId = id);
    reader.setCommentaryBook(id);
    _load();
  }

  /// A chip in the text: the strip shows its verse with the phrase lit. At rest
  /// the sheet goes to full height, where the strip is.
  void _light(MatnQuoteSpan quote) {
    setState(() {
      _quote = quote;
      _stripVerse = quote.verse;
    });
    if (!_full) _resize(full: true);
  }

  void _resize({required bool full}) {
    if (!_sheet.isAttached) return;
    final to = full ? _fullFraction : widget.half;
    if (MediaQuery.disableAnimationsOf(context)) {
      _sheet.jumpTo(to);
    } else {
      _sheet.animateTo(to, duration: TzMotion.long, curve: TzMotion.emphasized);
    }
  }

  bool _onExtent(DraggableScrollableNotification n) {
    final full = n.extent >= _fullFraction - 0.02;
    if (full != _full) setState(() => _full = full);
    // Dragged all the way down: closed.
    if (n.extent <= n.minExtent + 0.005) reader.closeCommentary();
    return false;
  }

  ScrollController? _scroll;

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical) _read(n.metrics);
    return false;
  }

  /// The share of the passage read: what is above the view's bottom edge.
  void _read(ScrollMetrics m) {
    if (!m.hasContentDimensions || !m.hasViewportDimension) return;
    final read = (m.pixels + m.viewportDimension) / (m.maxScrollExtent + m.viewportDimension);
    final p = read.clamp(0.0, 1.0);
    if ((p - _progress).abs() > 0.005) setState(() => _progress = p);
  }

  Book get _book => books.books.firstWhere((b) => b.id == _bookId);

  /// The verses the passage explains: the block's own range, or just the verse.
  (int, int) get _range {
    final b = _view?.block;
    return (b?.fromVerse ?? _verse, b?.toVerse ?? b?.fromVerse ?? _verse);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final height = box.maxHeight;
          // At full height the sheet stops 10 px under the status bar.
          _fullFraction = ((height - statusBarHeight(context) - 10) / height).clamp(0.5, 1.0);
          final half = widget.half.clamp(0.25, _fullFraction - 0.05);
          // The same list while the stop stands: a new one makes the sheet snap
          // again, which would cut a drag short on every rebuild.
          if (_snaps.single != half) _snaps = [half];
          return NotificationListener<DraggableScrollableNotification>(
            onNotification: _onExtent,
            child: DraggableScrollableSheet(
              controller: _sheet,
              initialChildSize: half,
              minChildSize: half * 0.45,
              maxChildSize: _fullFraction,
              snap: true,
              snapSizes: _snaps,
              builder: (context, scroll) => _surface(context, scroll),
            ),
          );
        },
      );

  Widget _surface(BuildContext context, ScrollController scroll) {
    _scroll = scroll;
    final c = TzTheme.of(context).colors;
    // Not a route: the verse behind the sheet stays reachable.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'الشرح: ${_book.shortTitle}',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            // The notch points at the verse while it shows above the sheet.
            child: VerseSheetSurface(
              surfaceKey: CommentarySheet.surfaceKey,
              notchKey: CommentarySheet.notchKey,
              notchX: _full || !widget.verseVisible ? null : widget.notchX,
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: CustomScrollView(
                  controller: scroll,
                  slivers: [
                    PinnedHeaderSliver(child: SizedBox(height: CommentarySheet.headerExtent, child: _header(context, c))),
                    // The verse, when it does not show behind the sheet: pinned over the text.
                    if (_view != null && (_full || !widget.verseVisible))
                      PinnedHeaderSliver(
                        child: ColoredBox(
                          color: c.surface,
                          // The 6 px under it are its own: scrolled text is cut clear of the strip.
                          child: Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 6), child: _strip()),
                        ),
                      ),
                    SliverToBoxAdapter(child: _body(context, c)),
                    const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
                  ],
                ),
              ),
            ),
          ),
          PositionedDirectional(start: 10, end: 10, bottom: 20, child: _stepper()),
        ],
      ),
    );
  }

  // The grab, a tab per book with expand and close, the byline and the verse, the progress line.
  Widget _header(BuildContext context, TzColors c) {
    final (from, to) = _range;
    final died = _book.deathYearH;
    final byline = [?_book.author, if (died != null) 'ت ${ar(died)}هـ'].join(' · ');
    return ColoredBox(
      color: c.surface,
      child: Stack(
        children: [
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                key: CommentarySheet.grabKey,
                width: 38,
                height: 5,
                decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(3)),
              ),
            ),
          ),
          PositionedDirectional(
            start: 18,
            end: 100,
            top: 11,
            height: 48,
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'الكتب',
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (i, book) in books.books.indexed) ...[
                      if (i > 0) const SizedBox(width: 18),
                      _tab(c, book),
                    ],
                  ],
                ),
              ),
            ),
          ),
          PositionedDirectional(
            end: 48,
            top: 13,
            child: _button(c, _full ? 'collapse' : 'expand', _full ? 'تصغير' : 'ملء الشاشة', () => _resize(full: !_full)),
          ),
          PositionedDirectional(end: 2, top: 13, child: _button(c, 'x', 'إغلاق الشرح', reader.closeCommentary)),
          PositionedDirectional(
            start: 18,
            end: 18,
            top: 59,
            child: Row(
              children: [
                Expanded(
                  child: Text(byline,
                      key: CommentarySheet.bylineKey,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TzType.caption.copyWith(color: c.ink3)),
                ),
                const SizedBox(width: 8),
                // The verse is never cut: at a large text size it shrinks to its share.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(from == to ? 'البيت ${ar(from)}' : 'الأبيات ${isolatedRange(from, to)}',
                        key: CommentarySheet.rangeKey,
                        style: TzType.caption.copyWith(color: c.ink3, fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 83,
            left: 16,
            right: 16,
            height: 2,
            child: Semantics(
              label: 'موضع القراءة',
              value: '${ar((_progress * 100).round())}٪',
              child: ColoredBox(
                key: CommentarySheet.progressKey,
                color: c.lineSoft,
                child: FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: _progress.clamp(0.0, 1.0),
                  child: DecoratedBox(decoration: BoxDecoration(color: c.lapis, borderRadius: BorderRadius.circular(2))),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // v2.css .books button: 44 px with a 2 px line under the chosen one, in a 48 px target.
  Widget _tab(TzColors c, Book book) {
    final on = book.id == _bookId;
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: on,
        child: InkWell(
          onTap: () => _chooseBook(book.id),
          child: Container(
            height: 48,
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              padding: const EdgeInsets.only(top: 10.8, bottom: 8.8),
              decoration:
                  BoxDecoration(border: Border(bottom: BorderSide(color: on ? c.lapis : Colors.transparent, width: 2))),
              child: Text(book.shortTitle,
                  style: TzType.label.copyWith(color: on ? c.ink : c.ink3, fontWeight: on ? FontWeight.w600 : FontWeight.w500)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _button(TzColors c, String icon, String label, VoidCallback onTap) => IconButton(
        tooltip: label,
        onPressed: onTap,
        icon: TzIcon(icon, size: 22, color: c.ink2),
        constraints: const BoxConstraints.tightFor(width: TzSize.touchTarget, height: TzSize.touchTarget),
        padding: EdgeInsets.zero,
      );

  Widget _body(BuildContext context, TzColors c) {
    final view = _view;
    if (view == null) return const SizedBox(height: 120);
    final parts = CommentaryParts(context,
        verseSize: reader.verseSize, quran: view.quran, quotes: view.quotes, activeQuote: _quote, onQuote: _light);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.legend && !_full) const CommentaryLegend(),
        Padding(
          padding: EdgeInsets.fromLTRB(20, _full || !widget.verseVisible ? 0 : 6, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (view.block.needsReview)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('هذا الموضع قيد المراجعة', style: TzType.caption.copyWith(color: c.carmine)),
                ),
              ...parts.text(view.reading, view.footnotes),
            ],
          ),
        ),
      ],
    );
  }

  // At full height the verse is behind the sheet: the strip carries it.
  Widget _strip() {
    final (from, to) = _range;
    final group = to > from;
    final shown = (_stripVerse ?? _verse).clamp(from, to);
    final v = reader.content.matn.verse(shown);
    final quote = _quote != null && _quote!.verse == shown ? _quote : null;
    final half = quote == null ? null : (quote.hemistich == 1 ? v.firstHemistich : v.secondHemistich);
    return MatnStrip(
      number: ar(shown),
      hemistichs: (v.firstHemistich, v.secondHemistich),
      rubrics: verseRubrics(reader.content, shown),
      caption: group ? 'يشرح الأبيات ${isolatedRange(from, to)}' : 'البيت ${ar(shown)} · المتن',
      verses: group ? [for (var n = from; n <= to; n++) ar(n)] : const [],
      current: shown - from,
      onVerse: (i) => setState(() {
        _stripVerse = from + i;
        if (_quote?.verse != from + i) _quote = null;
      }),
      highlight: half?.substring(quote!.verseStart, quote.verseEnd),
      highlightHemistich: quote?.hemistich,
      verseSize: reader.verseSize,
    );
  }

  // The neighbouring verses, and the passage's place in its chapter.
  Widget _stepper() {
    final (from, to) = _range;
    final matn = reader.content.matn;
    final chapter = matn.chapterOfVerse(from);
    final previous = from > 1 ? from - 1 : null, next = to < matn.lastVerse ? to + 1 : null;
    return BindingStepper(
      previous: previous == null ? '' : 'البيت ${ar(previous)}',
      next: next == null ? '' : 'البيت ${ar(next)}',
      step: ar(from - chapter.fromVerse + 1),
      caption: 'من ${ar(chapter.verseCount)} في الباب',
      onPrevious: previous == null ? null : () => reader.openCommentary(previous),
      onNext: next == null ? null : () => reader.openCommentary(next),
    );
  }
}

// lib/ui/reader/text_reader.dart — text mode (item 3.8, ADR 0021; handoff
// textmode-*): the matn as a poem, in one column.
//
// The chapters follow one another, each under its head (khatam, ordinal and
// range, the full title, a centred gilt rule); each verse is a unit with a small
// khatam in the margin and its two hemistichs staggered. The column opens on the
// reader's verse and follows it; the recited verse lies on the soft gilt wash,
// the chosen one (its menu open, or a selected run) is ringed. A tap moves the
// reader to a verse; a long press (or a double tap, as on the page) opens its
// menu. The size is the reader's choice of six (17–28 px).
//
// The poem has 1173 verses and no fixed heights, so the column is built around
// an anchor: the verse it opens on stands at the top of a list that grows down
// from it, over another that grows up from it. A verse out of reach makes a new
// anchor.
import 'package:flutter/material.dart';

import '../../data/matn_repository.dart';
import '../../utils/arabic.dart';
import '../design/components/chapter_head.dart';
import '../design/components/rubric.dart';
import '../design/components/verse_unit.dart';
import '../shell/shell_page.dart' show readingPadding;
import 'reader_controller.dart';
import 'verse_rubrics.dart';

/// The poem as a row of items: each chapter's head, then its verses.
class PoemItems {
  final MatnRepository matn;
  const PoemItems(this.matn);

  int get length => matn.lastVerse + matn.chapters.length;

  /// The head of the chapter at [chapterIndex] in the list of chapters.
  int headIndex(int chapterIndex) => matn.chapters[chapterIndex].fromVerse - 1 + chapterIndex;

  int verseIndex(int verse) => verse + matn.chapters.indexOf(matn.chapterOfVerse(verse));

  /// The item at [index]: a chapter (its head) or a verse number.
  ({MatnChapter chapter, int? verse}) at(int index) {
    // The last chapter whose head is at or before [index].
    var lo = 0, hi = matn.chapters.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (headIndex(mid) <= index) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final chapter = matn.chapters[lo], offset = index - headIndex(lo);
    return (chapter: chapter, verse: offset == 0 ? null : chapter.fromVerse + offset - 1);
  }
}

class TextReader extends StatefulWidget {
  final ReaderController reader;

  /// What floats over the column's end (the dock and the gap above it): the last
  /// verse scrolls clear of it.
  final double bottomInset;
  const TextReader({super.key, required this.reader, this.bottomInset = 0});

  @override
  State<TextReader> createState() => TextReaderState();
}

class TextReaderState extends State<TextReader> {
  final Map<int, GlobalKey> _rows = {};
  final Map<int, GlobalKey<VerseUnitState>> _units = {};
  late final PoemItems _items = PoemItems(_reader.content.matn);

  /// The item at the column's top when it was last laid out afresh, and how far
  /// above it the view starts (the item before it shows).
  late int _anchor;
  late double _lead;
  int _generation = 0;
  late int _followedVerse;

  ReaderController get _reader => widget.reader;

  @override
  void initState() {
    super.initState();
    _followedVerse = _reader.verse;
    _explained = _reader.commentaryVerse;
    _anchorOn(_explained ?? _reader.verse);
    _reader.addListener(_onReader);
  }

  @override
  void dispose() {
    _reader.removeListener(_onReader);
    super.dispose();
  }

  /// A chapter's first verse stands under its head; any other with the verse before it in view.
  void _anchorOn(int verse) {
    final chapter = _reader.content.matn.chapterOfVerse(verse);
    if (verse == chapter.fromVerse) {
      _anchor = _items.verseIndex(verse) - 1;
      _lead = 4; // v2.css .tm: 4 px above the first head
    } else {
      _anchor = _items.verseIndex(verse);
      _lead = 120;
    }
    _generation++;
  }

  int? _explained;

  void _onReader() {
    // The verse the commentary sheet explains stands above the sheet.
    final explained = _reader.commentaryVerse;
    if (explained != _explained) {
      _explained = explained;
      if (explained != null) WidgetsBinding.instance.addPostFrameCallback((_) => _standAbove(explained));
    }
    if (_reader.verse == _followedVerse) return;
    _followedVerse = _reader.verse;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(_followedVerse));
  }

  /// Brings [verse] into view: nothing if it is all on screen, a glide if its
  /// unit is built, a fresh anchor if it is out of reach.
  void _reveal(int verse) {
    if (!mounted) return;
    final row = _rows[verse]?.currentContext;
    if (row == null) {
      setState(() => _anchorOn(verse));
      return;
    }
    final box = rowRect(verse), viewport = context.findRenderObject() as RenderBox?;
    if (box != null && viewport != null && viewport.hasSize) {
      final view = viewport.localToGlobal(Offset.zero) & viewport.size;
      if (box.top >= view.top && box.bottom <= view.bottom - widget.bottomInset) return;
    }
    Scrollable.ensureVisible(
      row,
      alignment: 0.3,
      // Reduced motion (a system setting): the unit jumps into view instead of gliding.
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  /// Under the commentary sheet: [verse] is all in view above it, or the column
  /// is laid out afresh with the verse at its top.
  void _standAbove(int verse) {
    if (!mounted) return;
    final box = rowRect(verse), viewport = context.findRenderObject() as RenderBox?;
    if (box != null && viewport != null && viewport.hasSize) {
      final view = viewport.localToGlobal(Offset.zero) & viewport.size;
      if (box.top >= view.top && box.bottom <= view.bottom - widget.bottomInset) return;
    }
    setState(() => _anchorOn(verse));
  }

  /// Where the mark [mark] of [verse] is on screen, for placing a symbol's tip.
  Rect? symbolRect(int verse, Rubric mark) => _units[verse]?.currentState?.symbolRect(mark);

  /// Where [verse]'s unit is on screen, for anchoring the verse menu.
  Rect? rowRect(int verse) {
    final box = _rows[verse]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => _Column(
          key: ValueKey(_generation),
          length: _items.length,
          anchor: _anchor,
          lead: _lead,
          // On a tablet the column keeps a reading width.
          padding: readingPadding(box.maxWidth, side: 12),
          bottomInset: widget.bottomInset,
          itemBuilder: _item,
        ),
      );

  Widget _item(BuildContext context, int index) {
    final item = _items.at(index), chapter = item.chapter, matn = _reader.content.matn;
    final size = _reader.verseSize;
    final n = item.verse;
    if (n == null) {
      // The introduction is not a numbered chapter: its part's name stands for the ordinal.
      final numbered = chapter.orderIndex > 0;
      return ChapterHead(
        order: numbered ? ar(chapter.orderIndex) : '',
        caption: '${numbered ? chapterOrdinal(chapter.orderIndex) : matn.partOf(chapter).title} · '
            'الأبيات ${isolatedRange(chapter.fromVerse, chapter.toVerse)} · ${versesCount(chapter.verseCount)}',
        title: chapter.title,
        verseSize: size,
      );
    }
    final v = matn.verse(n);
    final sel = _reader.selection;
    final symbol = _reader.symbol;
    return KeyedSubtree(
      key: _rows.putIfAbsent(n, GlobalKey.new),
      child: VerseUnit(
        key: _units.putIfAbsent(n, GlobalKey<VerseUnitState>.new),
        number: ar(n),
        first: v.firstHemistich,
        second: v.secondHemistich,
        // Reader names and symbols in the rubric ink, unless the student hid them.
        rubrics: _reader.showRubric ? verseRubrics(_reader.content, n) : const [],
        onSymbol: (mark) => _reader.openSymbol(n, mark),
        activeSymbol: symbol != null && symbol.verse == n ? symbol.mark : null,
        fontSize: size,
        playing: _reader.playing && n == _reader.verse,
        chosen: n == _reader.menuVerse || n == _reader.commentaryVerse || (sel != null && sel.from <= n && n <= sel.to),
        onTap: () => _reader.tapVerse(n),
        onDoubleTap: () => _reader.openMenu(n),
        onLongPress: () => _reader.openMenu(n),
      ),
    );
  }
}

/// The column around its anchor: [anchor] at the top (less [lead]), the items
/// after it below, the items before it above. A new key lays it out afresh.
class _Column extends StatefulWidget {
  final int length, anchor;
  final double lead, bottomInset;
  final EdgeInsets padding;
  final IndexedWidgetBuilder itemBuilder;
  const _Column(
      {super.key,
      required this.length,
      required this.anchor,
      required this.lead,
      required this.padding,
      required this.bottomInset,
      required this.itemBuilder});

  @override
  State<_Column> createState() => _ColumnState();
}

class _ColumnState extends State<_Column> {
  static const _centre = ValueKey('text-reader-anchor');
  late final _scroll = ScrollController(initialScrollOffset: -widget.lead);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final side = EdgeInsets.only(left: widget.padding.left, right: widget.padding.right);
    return CustomScrollView(
      controller: _scroll,
      center: _centre,
      slivers: [
        SliverPadding(
          padding: side.copyWith(top: 4),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => widget.itemBuilder(context, widget.anchor - 1 - i),
              childCount: widget.anchor,
            ),
          ),
        ),
        SliverPadding(
          key: _centre,
          padding: side.copyWith(bottom: widget.bottomInset),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => widget.itemBuilder(context, widget.anchor + i),
              childCount: widget.length - widget.anchor,
            ),
          ),
        ),
      ],
    );
  }
}

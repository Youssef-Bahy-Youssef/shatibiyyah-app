// lib/ui/commentary/compare_screen.dart — «قارن الشروح» (plan P8, design board 1u).
//
// The three books on one verse. Wide (a landscape tablet): three columns, each
// with its book and author, the passage, and its source line under it (Siraj
// says it has no printed page numbers). Each column scrolls on its own;
// «مزامنة التمرير» (off by default — the books differ in length) keeps them at
// the same share of their length. Narrower: the columns are pages swiped
// sideways on the same verse.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/app_content.dart';
import '../../data/commentary_repository.dart';
import '../design/tokens.g.dart';
import '../../utils/arabic.dart';
import '../design/taysir_colors.dart';
import 'commentary_parts.dart';

/// From this width the books stand in columns; below it, they are pages.
const double kCompareColumnsMinWidth = 840;

class CompareScreen extends StatefulWidget {
  final AppContent content;
  final int verse;
  const CompareScreen({super.key, required this.content, required this.verse});

  static Future<void> open(BuildContext context, AppContent content, int verse) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CompareScreen(content: content, verse: verse),
    ),
  );

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  List<Book> get _books => widget.content.books.books;
  late final _views = <String, Future<BlockView?>>{
    for (final b in _books) b.id: loadBlockView(widget.content.books, b.id, widget.verse),
  };
  late final _scrolls = {for (final b in _books) b.id: ScrollController()};
  final _pages = PageController();
  int _page = 0;
  bool _sync = false;
  bool _syncing = false;

  @override
  void dispose() {
    for (final c in _scrolls.values) {
      c.dispose();
    }
    _pages.dispose();
    super.dispose();
  }

  /// With «مزامنة التمرير», the other columns follow [from] at the same share of their length.
  bool _onScroll(String from, ScrollNotification n) {
    if (!_sync || _syncing || n is! ScrollUpdateNotification || n.dragDetails == null) return false;
    final m = n.metrics;
    final share = m.maxScrollExtent <= 0 ? 0.0 : (m.pixels / m.maxScrollExtent).clamp(0.0, 1.0);
    _syncing = true;
    for (final MapEntry(key: id, value: c) in _scrolls.entries) {
      if (id != from && c.hasClients) c.jumpTo(c.position.maxScrollExtent * share);
    }
    _syncing = false;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, box) {
              final columns = box.maxWidth >= kCompareColumnsMinWidth;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(t, columns),
                  Expanded(child: columns ? _columns(t) : _pageView(t)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(TaysirColors t, bool columns) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'إغلاق المقارنة',
                icon: Icon(LucideIcons.x, size: 21, color: t.text),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Text('قارن الشروح', style: TzType.display.copyWith(color: t.text)),
              ),
              if (columns)
                MergeSemantics(
                  child: Row(
                    children: [
                      Text('مزامنة التمرير', style: TzType.label.copyWith(color: t.dim)),
                      Switch(
                        value: _sync,
                        onChanged: (on) => setState(() => _sync = on),
                        activeThumbColor: t.onGold,
                        activeTrackColor: t.gold,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (columns) _verseCard(t),
        ],
      ),
    );
  }

  /// The verse on top: fixed over the columns; inside each page's scroll on a phone.
  Widget _verseCard(TaysirColors t) {
    final v = widget.content.matn.verse(widget.verse);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsetsDirectional.only(start: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: t.panel2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.line),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  ar(widget.verse),
                  textAlign: TextAlign.center,
                  style: TzType.head.copyWith(color: t.goldText),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      v.firstHemistich,
                      textAlign: TextAlign.start,
                      style: TzType.verse.copyWith(color: t.text),
                    ),
                    Text(
                      v.secondHemistich,
                      textAlign: TextAlign.end,
                      style: TzType.verse.copyWith(color: t.text),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _columns(TaysirColors t) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < _books.length; i++) ...[
        if (i > 0) VerticalDivider(width: 1, thickness: 1, color: t.line),
        Expanded(child: _column(t, _books[i], pinned: true)),
      ],
    ],
  );

  Widget _pageView(TaysirColors t) => Column(
    children: [
      // Which book is showing, and a way to move without swiping.
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _books.length; i++)
            Semantics(
              button: true,
              selected: i == _page,
              label: _books[i].shortTitle,
              excludeSemantics: true,
              child: InkWell(
                onTap: () =>
                    _pages.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: Container(
                      width: i == _page ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? t.gold : t.line,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      Expanded(
        child: PageView(
          controller: _pages,
          onPageChanged: (i) => setState(() => _page = i),
          children: [for (final b in _books) _column(t, b, pinned: false)],
        ),
      ),
    ],
  );

  /// A book's column. [pinned] (the wide layout): its heading stays on top and its
  /// source line at the bottom. Otherwise (a page on a phone) the verse, heading,
  /// text and source line scroll together, so large text still fits.
  Widget _column(TaysirColors t, Book book, {required bool pinned}) {
    final year = book.deathYearH;
    final by = [?(book.author ?? book.authorFull), if (year != null) 'ت ${ar(year)}هـ'].join(' · ');
    final heading = Padding(
      padding: EdgeInsets.fromLTRB(pinned ? 16 : 0, 12, pinned ? 16 : 0, pinned ? 8 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(book.title, style: TzType.title.copyWith(color: t.goldText)),
          if (by.isNotEmpty) Text(by, style: TzType.caption.copyWith(color: t.muted)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pinned) heading,
        Expanded(
          child: FutureBuilder<BlockView?>(
            future: _views[book.id],
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Center(child: CircularProgressIndicator(color: t.gold));
              }
              final view = snap.data;
              if (view == null) {
                return Center(
                  child: Text('لا شرح لهذا البيت في هذا الكتاب', style: TzType.label.copyWith(color: t.dim)),
                );
              }
              final parts = CommentaryParts(context, verseSize: 18.4, quran: view.quran, quotes: view.quotes);
              final items = [
                if (!pinned) ...[_verseCard(t), heading],
                if (view.block.grouped)
                  parts.chip(
                    LucideIcons.layers,
                    'يشرح الأبيات ${ar(view.block.fromVerse!)}–${ar(view.block.toVerse!)} معًا',
                  ),
                ...parts.text(view.main, view.footnotes),
                if (!pinned && view.sources.isNotEmpty) parts.sourceLine(view.sources),
              ];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (n) => _onScroll(book.id, n),
                      child: ListView.separated(
                        controller: _scrolls[book.id],
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => items[i],
                      ),
                    ),
                  ),
                  if (pinned && view.sources.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: parts.sourceLine(view.sources, boxed: false),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

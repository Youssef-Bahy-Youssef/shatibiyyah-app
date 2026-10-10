// lib/ui/commentary/commentary_screen.dart — «الشرح»: the three bundled books, verse by verse.
//
// v3 prototype, screen "commentary": a close button and «{book} · البيت N»; a tab per
// book; «المعنى / اللغة» pills when Al-Wafi has a language section for the verse;
// the verse(s) quoted on top; «يشرح الأبيات a–b معًا» for grouped explanations;
// headed paragraphs with tappable footnote markers; footnotes without a placeable
// marker listed after the text; the source line; previous / next explanation.
// Quranic-quote colouring waits for G-07.
//
// The content is a CommentaryPane, which the tablet's split view (plan P8) hosts
// beside the page: it can follow a verse given from outside, holding while the
// student scrolls in it.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/app_content.dart';
import '../../data/commentary_repository.dart';
import '../../data/settings_store.dart' show kDefaultVerseSize;
import '../design/tokens.g.dart';
import '../design/tz_type.dart';
import '../../utils/arabic.dart';
import '../design/pill_tabs.dart';
import '../design/taysir_colors.dart';
import '../shell/shell_page.dart' show readingPadding;
import 'commentary_parts.dart';

/// How long after the student's last scroll in the pane a new verse from outside
/// waits before it replaces the passage being read.
const Duration kHoldAfterScroll = Duration(seconds: 6);

class CommentaryScreen extends StatelessWidget {
  final AppContent content;
  final int verse;
  final String? bookId; // default: the default book
  const CommentaryScreen({super.key, required this.content, required this.verse, this.bookId});

  /// Told each time a passage is shown: a day of use for the rating prompt (set at
  /// boot; ADR 0008).
  static void Function()? onOpened;

  static Future<void> open(BuildContext context, AppContent content, int verse, {String? bookId}) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CommentaryScreen(content: content, verse: verse, bookId: bookId),
      ));

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          bottom: false,
          child: CommentaryPane(
            content: content,
            verse: verse,
            bookId: bookId,
            header: (context, title) => SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'إغلاق',
                    icon: Icon(LucideIcons.x, color: t.text, size: 21),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TzType.display.copyWith(color: t.text)),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A book's explanation of a verse: the tabs, the passage, previous / next.
class CommentaryPane extends StatefulWidget {
  final AppContent content;

  /// The verse to explain. A new value moves the pane there — unless the passage
  /// shown already covers it, or the student scrolled in the pane within
  /// [kHoldAfterScroll] (then it moves once that time has passed).
  final int verse;
  final String? bookId;
  final double textScale;

  /// Drawn above the tabs with the title («الوافي · البيت ٢٢٦»).
  final Widget Function(BuildContext context, String title)? header;

  /// Told of each passage shown.
  final void Function(BlockRef block)? onShown;

  /// The student moved in the book themselves (a tab, previous / next).
  final VoidCallback? onNavigate;

  const CommentaryPane({
    super.key,
    required this.content,
    required this.verse,
    this.bookId,
    this.textScale = 1,
    this.header,
    this.onShown,
    this.onNavigate,
  });

  @override
  State<CommentaryPane> createState() => _CommentaryPaneState();
}

class _CommentaryPaneState extends State<CommentaryPane> {
  CommentaryRepository get books => widget.content.books;
  late String _bookId = widget.bookId ?? books.defaultBook.id;
  late int _verse = widget.verse; // the verse the pane is anchored on
  BlockView? _view;
  bool _language = false;
  final _scroll = ScrollController();
  Timer? _hold; // running while the student's last scroll is recent
  int? _pendingVerse; // a verse from outside that arrived meanwhile

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CommentaryPane old) {
    super.didUpdateWidget(old);
    if (widget.verse != old.verse) _follow(widget.verse);
  }

  @override
  void dispose() {
    _hold?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _follow(int verse) {
    final b = _view?.block;
    if (b != null && b.bookId == _bookId && b.fromVerse != null && verse >= b.fromVerse! && verse <= b.toVerse!) {
      _pendingVerse = null;
      return; // the passage shown already explains it
    }
    if (_hold != null) {
      _pendingVerse = verse; // the student is reading: after the hold
      return;
    }
    _verse = verse;
    _load();
  }

  /// A scroll by the student starts (or extends) the hold on verses from outside.
  void _userScrolled() {
    _hold?.cancel();
    _hold = Timer(kHoldAfterScroll, () {
      _hold = null;
      final v = _pendingVerse;
      _pendingVerse = null;
      if (v != null && mounted) _follow(v);
    });
  }

  Future<void> _load({BlockRef? block}) async {
    final view = await loadBlockView(books, _bookId, _verse, block: block);
    if (!mounted) return;
    if (view == null) {
      setState(() => _view = null);
      return;
    }
    final ref = view.block;
    setState(() {
      _view = view;
      _language = false;
      if (ref.fromVerse != null && (_verse < ref.fromVerse! || _verse > ref.toVerse!)) _verse = ref.fromVerse!;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    widget.onShown?.call(ref);
    CommentaryScreen.onOpened?.call();
  }

  Future<void> _step(int direction) async {
    final view = _view;
    if (view == null) return;
    final next = await books.neighbour(view.block, direction);
    if (next != null) {
      widget.onNavigate?.call();
      _verse = next.fromVerse!;
      await _load(block: next);
    }
  }

  Book get _book => books.books.firstWhere((b) => b.id == _bookId);

  String _title() {
    final b = _view?.block;
    final range = (b != null && b.grouped)
        ? 'الأبيات ${ar(b.fromVerse!)}–${ar(b.toVerse!)}'
        : 'البيت ${ar(b?.fromVerse ?? _verse)}';
    return '${_book.shortTitle} · $range';
  }

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return Column(
      children: [
        if (widget.header case final header?) header(context, _title()),
        _tabs(t),
        Expanded(child: _body(t)),
      ],
    );
  }

  Widget _tabs(TaysirColors t) => DecoratedBox(
        decoration: BoxDecoration(color: t.bg, border: Border(bottom: BorderSide(color: t.line))),
        child: Row(
          children: [
            for (final book in books.books)
              Expanded(
                child: Semantics(
                  selected: book.id == _bookId,
                  button: true,
                  child: InkWell(
                    onTap: book.id == _bookId
                        ? null
                        : () {
                            setState(() => _bookId = book.id);
                            widget.onNavigate?.call();
                            _load();
                          },
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: book.id == _bookId ? t.gold : Colors.transparent, width: 3),
                        ),
                      ),
                      child: Text(book.shortTitle,
                          style: TzType.label.copyWith(color: book.id == _bookId ? t.goldText : t.dim)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _body(TaysirColors t) {
    final view = _view;
    if (view == null) {
      return Center(child: CircularProgressIndicator(color: t.gold));
    }
    final parts = CommentaryParts(context,
        verseSize: kDefaultVerseSize * widget.textScale, quran: view.quran, quotes: view.quotes);
    final language = view.language;
    final shown = _language && language.isNotEmpty ? language : view.main;
    final items = <Widget>[
      if (language.isNotEmpty) _segmentPills(t),
      ..._quotes(t, view.block),
      if (view.block.grouped)
        parts.chip(LucideIcons.layers, 'يشرح الأبيات ${ar(view.block.fromVerse!)}–${ar(view.block.toVerse!)} معًا'),
      if (view.block.needsReview) parts.chip(LucideIcons.triangleAlert, 'هذا الموضع قيد المراجعة', warn: true),
      ...parts.text(shown, view.footnotes, withNotes: !_language),
      if (view.sources.isNotEmpty) parts.sourceLine(view.sources),
      _prevNext(t),
    ];

    // The student's own scrolling holds a verse change from outside (see [CommentaryPane.verse]).
    return NotificationListener<UserScrollNotification>(
      onNotification: (n) {
        if (n.direction != ScrollDirection.idle) _userScrolled();
        return false;
      },
      child: LayoutBuilder(
        builder: (context, box) => ListView.separated(
          controller: _scroll,
          padding: readingPadding(box.maxWidth, side: 18, top: 12, bottom: 24),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) => items[i],
        ),
      ),
    );
  }

  Widget _segmentPills(TaysirColors t) => PillTabs<bool>(
        options: const {false: 'المعنى', true: 'اللغة'},
        selected: _language,
        onSelect: (language) => setState(() => _language = language),
        track: t.bg,
      );

  List<Widget> _quotes(TaysirColors t, BlockRef block) {
    final from = block.fromVerse ?? _verse;
    final to = block.toVerse ?? from;
    final matn = widget.content.matn;
    return [
      for (var n = from; n <= to && n < from + 3; n++)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: t.panel2, borderRadius: BorderRadius.circular(16), border: Border.all(color: t.line)),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: t.gold, width: 1.5)),
                child: Text(ar(n), style: TzType.head.copyWith(color: t.goldText)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(matn.verse(n).firstHemistich,
                        textAlign: TextAlign.right, style: TzType.verse.scaled(widget.textScale).copyWith(color: t.text)),
                    Text(matn.verse(n).secondHemistich,
                        textAlign: TextAlign.left, style: TzType.verse.scaled(widget.textScale).copyWith(color: t.text)),
                  ],
                ),
              ),
            ],
          ),
        ),
      if (to - from + 1 > 3)
        Text(_moreVerses(to - from - 2), style: TzType.caption.copyWith(color: t.muted)),
    ];
  }

  /// «وبيت آخر» / «وبيتان آخران» / «و٣ أبيات أخرى» / «و١١ بيتًا آخر».
  static String _moreVerses(int n) => switch (n) {
        1 => 'وبيت آخر في هذا الشرح',
        2 => 'وبيتان آخران في هذا الشرح',
        <= 10 => 'و${ar(n)} أبيات أخرى في هذا الشرح',
        _ => 'و${ar(n)} بيتًا آخر في هذا الشرح',
      };

  Widget _prevNext(TaysirColors t) {
    Widget button(String label, IconData icon, int direction) => Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _step(direction),
            icon: Icon(icon, size: 17, color: t.text),
            label: Text(label, style: TzType.label.copyWith(color: t.text)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: BorderSide(color: t.line),
              shape: const StadiumBorder(),
            ),
          ),
        );
    return Row(children: [
      button('السابق', LucideIcons.chevronRight, -1),
      const SizedBox(width: 10),
      button('التالي', LucideIcons.chevronLeft, 1),
    ]);
  }
}

// lib/ui/commentary/commentary_screen.dart — «الشرح»: the three bundled books, verse by verse.
//
// v3 prototype, screen "commentary": a close button and «{book} · البيت N»; a tab per
// book; «المعنى / اللغة» pills when Al-Wafi has a language section for the verse;
// the verse(s) quoted on top; «يشرح الأبيات a–b معًا» for grouped explanations;
// headed paragraphs with tappable footnote markers; footnotes without a placeable
// marker listed after the text; the source line; previous / next explanation.
// Quranic-quote colouring is not in M1 (v2.1, migration plan G-07).
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/app_content.dart';
import '../../data/commentary_repository.dart';
import '../../domain/commentary_text.dart';
import '../../theme.dart' show kufi, naskh;
import '../../utils/arabic.dart';
import '../design/pill_tabs.dart';
import '../design/taysir_colors.dart';

class CommentaryScreen extends StatefulWidget {
  final AppContent content;
  final int verse;
  final String? bookId; // default: the default book
  const CommentaryScreen({super.key, required this.content, required this.verse, this.bookId});

  /// Told each passage shown, for «السجل» (set at boot; features-v3 reading-history).
  static void Function(String bookId, int fromVerse, int toVerse)? onRead;

  static Future<void> open(BuildContext context, AppContent content, int verse, {String? bookId}) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CommentaryScreen(content: content, verse: verse, bookId: bookId),
      ));

  @override
  State<CommentaryScreen> createState() => _CommentaryScreenState();
}

/// Everything shown for one block, loaded together so a tab switch never shows a mix.
class _BlockView {
  final BlockRef block;
  final List<Segment> segments;
  final List<Footnote> footnotes;
  final List<BlockSource> sources;
  const _BlockView(this.block, this.segments, this.footnotes, this.sources);
}

class _CommentaryScreenState extends State<CommentaryScreen> {
  CommentaryRepository get books => widget.content.books;
  late String _bookId = widget.bookId ?? books.defaultBook.id;
  late int _verse = widget.verse; // the verse the reader is anchored on
  _BlockView? _view;
  bool _language = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({BlockRef? block}) async {
    final ref = block ?? (await books.blocksForVerse(_bookId, _verse)).firstOrNull;
    if (ref == null) {
      if (mounted) setState(() => _view = null);
      return;
    }
    final view = _BlockView(
      ref,
      await books.segments(ref.id),
      await books.footnotes(ref.id),
      await books.sources(ref.id),
    );
    if (!mounted) return;
    setState(() {
      _view = view;
      _language = false;
      if (ref.fromVerse != null && (_verse < ref.fromVerse! || _verse > ref.toVerse!)) _verse = ref.fromVerse!;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    final from = ref.fromVerse;
    if (from != null) CommentaryScreen.onRead?.call(ref.bookId, from, ref.toVerse ?? from);
  }

  Future<void> _step(int direction) async {
    final view = _view;
    if (view == null) return;
    final next = await books.neighbour(view.block, direction);
    if (next != null) {
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _header(t),
              _tabs(t),
              Expanded(child: _body(t)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(TaysirColors t) => SizedBox(
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
              child: Text(_title(),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: kufi(size: 20, weight: 600, color: t.text)),
            ),
            const SizedBox(width: 12),
          ],
        ),
      );

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
                          style: kufi(
                              size: 14,
                              weight: book.id == _bookId ? 600 : 400,
                              color: book.id == _bookId ? t.goldText : t.dim)),
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
    final language = view.segments.where((s) => s.isLanguage).toList();
    final main = view.segments.where((s) => !s.isLanguage && s.type != 'citation_lead_in').toList();
    final shown = _language && language.isNotEmpty ? language : main;
    final placed = <String>{};
    final items = <Widget>[];

    if (language.isNotEmpty) items.add(_segmentPills(t));
    items.addAll(_quotes(t, view.block));
    if (view.block.grouped) {
      items.add(_chip(t, LucideIcons.layers,
          'يشرح الأبيات ${ar(view.block.fromVerse!)}–${ar(view.block.toVerse!)} معًا'));
    }
    if (view.block.needsReview) {
      items.add(_chip(t, LucideIcons.triangleAlert, 'هذا الموضع قيد المراجعة', warn: true));
    }
    for (final segment in shown) {
      final notes = view.footnotes.where((f) => f.segmentId == segment.id).toList();
      final heading = segment.heading;
      if (heading != null && heading.trim().isNotEmpty && !heading.startsWith('[')) {
        items.add(Align(alignment: AlignmentDirectional.centerStart, child: _headingPill(t, heading)));
      }
      for (final paragraph in layoutSegment(segment.text, notes)) {
        for (final run in paragraph.runs) {
          if (run.isMarker) placed.add(run.footnote!.id);
        }
        items.add(_paragraph(t, paragraph));
      }
    }
    final unplaced = view.footnotes.where((f) => !placed.contains(f.id)).toList();
    if (unplaced.isNotEmpty && !_language) items.add(_notesList(t, unplaced));
    if (view.sources.isNotEmpty) items.add(_sourceLine(t, view.sources));
    items.add(_prevNext(t));

    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => items[i],
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
                child: Text(ar(n), style: naskh(size: 15, weight: FontWeight.w700, color: t.goldText)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(matn.verse(n).firstHemistich,
                        textAlign: TextAlign.right, style: naskh(size: 18, height: 1.65, color: t.text)),
                    Text(matn.verse(n).secondHemistich,
                        textAlign: TextAlign.left, style: naskh(size: 18, height: 1.65, color: t.text)),
                  ],
                ),
              ),
            ],
          ),
        ),
      if (to - from + 1 > 3)
        Text(_moreVerses(to - from - 2), style: kufi(size: 12.5, weight: 400, color: t.muted)),
    ];
  }

  Widget _chip(TaysirColors t, IconData icon, String label, {bool warn = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: (warn ? t.warn : t.gold).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: warn ? t.warn : t.goldDeep),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: warn ? t.warn : t.goldText),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: kufi(size: 13.5, weight: 600, color: warn ? t.warn : t.goldText))),
          ],
        ),
      );

  // No `alignment` on the Container: that would stretch the pill to the full width.
  Widget _headingPill(TaysirColors t, String heading) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(color: t.gold.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
        child: Text(heading, style: kufi(size: 13.5, weight: 600, color: t.goldText)),
      );

  /// «وبيت آخر» / «وبيتان آخران» / «و٣ أبيات أخرى» / «و١١ بيتًا آخر».
  static String _moreVerses(int n) => switch (n) {
        1 => 'وبيت آخر في هذا الشرح',
        2 => 'وبيتان آخران في هذا الشرح',
        <= 10 => 'و${ar(n)} أبيات أخرى في هذا الشرح',
        _ => 'و${ar(n)} بيتًا آخر في هذا الشرح',
      };

  Widget _paragraph(TaysirColors t, CommentaryParagraph paragraph) {
    final base = naskh(size: 19, height: 1.95, color: t.text);
    return Text.rich(
      TextSpan(style: base, children: [
        for (final run in paragraph.runs)
          if (run.isMarker)
            WidgetSpan(
              alignment: PlaceholderAlignment.top,
              child: Semantics(
                button: true,
                label: 'حاشية ${run.text}',
                child: GestureDetector(
                  onTap: () => _showFootnote(t, run.footnote!),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(run.text, style: naskh(size: 13, weight: FontWeight.w700, color: t.goldText)),
                  ),
                ),
              ),
            )
          else
            TextSpan(text: run.text),
      ]),
      textAlign: TextAlign.justify,
    );
  }

  void _showFootnote(TaysirColors t, Footnote note) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: t.panel,
        showDragHandle: true,
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('حاشية ${note.marker ?? ''}', style: kufi(size: 15, weight: 600, color: t.goldText)),
                const SizedBox(height: 10),
                Text(note.text, style: naskh(size: 17, height: 1.8, color: t.text)),
              ],
            ),
          ),
        ),
      );

  Widget _notesList(TaysirColors t, List<Footnote> notes) => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
            color: t.panel2, borderRadius: BorderRadius.circular(16), border: Border.all(color: t.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('الحواشي', style: kufi(size: 13.5, weight: 600, color: t.goldText)),
            for (final n in notes)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${n.marker != null ? '(${n.marker}) ' : ''}${n.text}',
                    style: naskh(size: 16, height: 1.7, color: t.dim)),
              ),
          ],
        ),
      );

  static String _range(List<int> pages) {
    if (pages.isEmpty) return '';
    final sorted = pages.toSet().toList()..sort();
    return sorted.length == 1 ? ar(sorted.first) : '${ar(sorted.first)}–${ar(sorted.last)}';
  }

  Widget _sourceLine(TaysirColors t, List<BlockSource> sources) {
    final quranpedia = sources.where((s) => s.provider == 'quranpedia').toList();
    final other = sources.where((s) => s.provider != 'quranpedia').toList();
    final printed = sources.map((s) => s.printedPage).whereType<int>().toList();
    final parts = [
      if (quranpedia.isNotEmpty) 'قرآنبيديا ص ${_range(quranpedia.map((s) => s.sourcePage).toList())}',
      if (other.isNotEmpty) 'مكتبة أهل البيت ص ${_range(other.map((s) => s.sourcePage).toList())}',
      printed.isEmpty ? 'لا ترقيم مطبوع' : 'الطبعة ص ${_range(printed)}',
    ];
    final url = sources.map((s) => s.url).whereType<String>().firstOrNull;
    return Semantics(
      link: url != null,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: url == null ? null : () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: t.panel2, borderRadius: BorderRadius.circular(16), border: Border.all(color: t.line)),
          child: Row(
            children: [
              Icon(LucideIcons.libraryBig, size: 16, color: t.goldText),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('المصدر: ${parts.join(' · ')}', style: kufi(size: 13, weight: 400, color: t.dim))),
              if (url != null) Icon(LucideIcons.externalLink, size: 15, color: t.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _prevNext(TaysirColors t) {
    Widget button(String label, IconData icon, int direction) => Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _step(direction),
            icon: Icon(icon, size: 17, color: t.text),
            label: Text(label, style: kufi(size: 14.5, weight: 400, color: t.text)),
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

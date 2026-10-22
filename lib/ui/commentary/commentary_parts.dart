// lib/ui/commentary/commentary_parts.dart — what every view of a commentary passage
// shares (item 3.9): loading one block with its segments, footnotes, quotations
// and sources together, and drawing its text: segment headings, justified
// paragraphs with the Quranic quotations in lapis ﴿ ﴾, the book's quotations of
// the verse as chips, footnote markers, the notes collected under the text, and
// the source line. Used by the commentary sheet, the tablet's split panel and
// «قارن الشروح».
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/commentary_repository.dart';
import '../../domain/commentary_text.dart';
import '../../utils/arabic.dart';
import '../design/components/commentary_inline.dart';
import '../design/components/verse_unit.dart' show kVerseSize;
import '../design/taysir_colors.dart';
import '../design/tokens.g.dart';
import '../design/tz_theme.dart';
import '../design/components/tz_motion.dart';

/// Everything shown for one block, loaded together so a tab switch never shows a mix.
class BlockView {
  final BlockRef block;
  final List<Segment> segments;
  final List<Footnote> footnotes;
  final List<BlockSource> sources;
  final List<QuranSpan> quran;
  final List<MatnQuoteSpan> quotes;
  const BlockView(this.block, this.segments, this.footnotes, this.sources,
      {this.quran = const [], this.quotes = const []});

  List<Segment> get language => segments.where((s) => s.isLanguage).toList();
  List<Segment> get main => segments.where((s) => !s.isLanguage && s.type != 'citation_lead_in').toList();

  /// The passage as it reads, every part in the book's order (the lead-in that
  /// only repeats the verse is left out).
  List<Segment> get reading => segments.where((s) => s.type != 'citation_lead_in').toList();
}

/// [block], or the first block of [bookId] explaining [verse]; null when there is none.
Future<BlockView?> loadBlockView(CommentaryRepository books, String bookId, int verse, {BlockRef? block}) async {
  final ref = block ?? (await books.blocksForVerse(bookId, verse)).firstOrNull;
  if (ref == null) return null;
  return BlockView(ref, await books.segments(ref.id), await books.footnotes(ref.id), await books.sources(ref.id),
      quran: await books.quranSpans(ref.id), quotes: await books.matnQuotes(ref.id));
}

/// The heading over [segment]: the book's own, or the kind's name where the book
/// only brackets it («[اللغة] (١)»).
String? segmentHeading(Segment segment) {
  final own = segment.heading?.trim() ?? '';
  if (own.isNotEmpty && !own.startsWith('[')) return own;
  return switch (segment.type) {
    'meaning' => 'المعنى',
    'language' => 'اللغة',
    'language_and_meaning' => 'اللغة والمعنى',
    _ => null,
  };
}

/// The drawing of a passage, at the reader's verse size.
class CommentaryParts {
  final BuildContext context;
  final double verseSize;

  /// The quotations of [BlockView] to mark in the text.
  final List<QuranSpan> quran;
  final List<MatnQuoteSpan> quotes;

  /// The quote whose phrase is lit in the matn strip, and what a tap on a chip does.
  final MatnQuoteSpan? activeQuote;
  final void Function(MatnQuoteSpan quote)? onQuote;

  final Map<String, GlobalKey> _noteKeys = {};

  CommentaryParts(this.context,
      {this.verseSize = kVerseSize, this.quran = const [], this.quotes = const [], this.activeQuote, this.onQuote});

  TaysirColors get t => TaysirColors.of(context);
  TzColors get _c => TzTheme.of(context).colors;

  /// The headed paragraphs of [segments], then every note of the passage under
  /// its number (unless [withNotes] is false).
  List<Widget> text(List<Segment> segments, List<Footnote> footnotes, {bool withNotes = true}) {
    final items = <Widget>[];
    for (final segment in segments) {
      final notes = footnotes.where((f) => f.segmentId == segment.id).toList();
      if (segmentHeading(segment) case final heading?) items.add(SegmentHeading(heading));
      final paragraphs = layoutSegment(segment.text, notes,
          quran: [for (final q in quran) if (q.segmentId == segment.id) q],
          quotes: [for (final q in quotes) if (q.segmentId == segment.id) q]);
      items.addAll(paragraphs.map(paragraph));
    }
    final shown = {for (final s in segments) s.id};
    final listed = [for (final f in footnotes) if (f.segmentId == null || shown.contains(f.segmentId)) f];
    if (listed.isNotEmpty && withNotes) items.add(notesList(listed));
    return items;
  }

  Widget chip(IconData icon, String label, {bool warn = false}) => Container(
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
        Expanded(
          child: Text(label, style: TzType.label.copyWith(color: warn ? t.warn : t.goldText)),
        ),
      ],
    ),
  );

  /// One paragraph (v2.css .c-body p): justified, 12 px under it.
  Widget paragraph(CommentaryParagraph paragraph) {
    final base = commentaryStyle(_c, verseSize);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text.rich(
        TextSpan(
          style: base,
          children: [
            for (final run in paragraph.runs)
              if (run.footnote case final note?)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: FootnoteMarker(label: run.text, onTap: () => showFootnote(note)),
                )
              else if (run.quran != null)
                quranSpan(run.text, _c)
              else if (run.quote case final quote?)
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: QuoteChip(
                    words: run.text,
                    style: base,
                    on: identical(quote, activeQuote),
                    onTap: onQuote == null ? null : () => onQuote!(quote),
                  ),
                )
              else
                ...withReferences(run.text, _c),
          ],
        ),
        textAlign: TextAlign.justify,
      ),
    );
  }

  /// A marker brings its note, under the text, into view.
  void showFootnote(Footnote note) {
    final target = _noteKeys[note.id]?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(target,
        alignment: 0.5,
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : TzMotion.medium,
        curve: TzMotion.standard);
  }

  Widget notesList(List<Footnote> notes) => FootnoteList(notes: [
        for (final n in notes) (marker: n.marker, text: n.text, key: _noteKeys.putIfAbsent(n.id, GlobalKey.new)),
      ]);

  static String _range(List<int> pages) {
    if (pages.isEmpty) return '';
    final sorted = pages.toSet().toList()..sort();
    return sorted.length == 1 ? ar(sorted.first) : '${ar(sorted.first)}–${ar(sorted.last)}';
  }

  /// «المصدر: قرآنبيديا ص … · الطبعة ص …» (a link to the source page when there is one).
  Widget sourceLine(List<BlockSource> sources, {bool boxed = true}) {
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
      child: TzPressable(sink: true,
        borderRadius: BorderRadius.circular(16),
        onTap: url == null ? null : () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: boxed
              ? BoxDecoration(
                  color: t.panel2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: t.line),
                )
              : null,
          child: Row(
            children: [
              Icon(LucideIcons.libraryBig, size: 16, color: t.goldText),
              const SizedBox(width: 8),
              Expanded(
                child: Text('المصدر: ${parts.join(' · ')}', style: TzType.label.copyWith(color: t.dim)),
              ),
              if (url != null) Icon(LucideIcons.externalLink, size: 15, color: t.muted),
            ],
          ),
        ),
      ),
    );
  }
}

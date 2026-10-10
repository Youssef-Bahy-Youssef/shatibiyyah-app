// lib/ui/commentary/commentary_parts.dart — what every view of a commentary passage
// shares: loading one block with its segments, footnotes and sources together, and
// drawing its paragraphs (tappable footnote markers), heading pills, the notes that
// have no placeable marker, and the source line. Used by the phone's «الشرح»
// screen, the tablet's split panel and «قارن الشروح».
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/commentary_repository.dart';
import '../../domain/commentary_text.dart';
import '../design/tokens.g.dart';
import '../design/tz_type.dart';
import '../../utils/arabic.dart';
import '../design/taysir_colors.dart';

/// Everything shown for one block, loaded together so a tab switch never shows a mix.
class BlockView {
  final BlockRef block;
  final List<Segment> segments;
  final List<Footnote> footnotes;
  final List<BlockSource> sources;
  const BlockView(this.block, this.segments, this.footnotes, this.sources);

  List<Segment> get language => segments.where((s) => s.isLanguage).toList();
  List<Segment> get main => segments.where((s) => !s.isLanguage && s.type != 'citation_lead_in').toList();
}

/// [block], or the first block of [bookId] explaining [verse]; null when there is none.
Future<BlockView?> loadBlockView(CommentaryRepository books, String bookId, int verse, {BlockRef? block}) async {
  final ref = block ?? (await books.blocksForVerse(bookId, verse)).firstOrNull;
  if (ref == null) return null;
  return BlockView(ref, await books.segments(ref.id), await books.footnotes(ref.id), await books.sources(ref.id));
}

/// The drawing of a passage, at a text [scale] (the split panel's «حجم الخط»).
class CommentaryParts {
  final BuildContext context;
  final TaysirColors t;
  final double scale;
  const CommentaryParts(this.context, this.t, {this.scale = 1});

  /// The headed paragraphs of [segments], then the notes whose marker could not be
  /// placed in the text (unless [withNotes] is false).
  List<Widget> text(List<Segment> segments, List<Footnote> footnotes, {bool withNotes = true}) {
    final placed = <String>{};
    final items = <Widget>[];
    for (final segment in segments) {
      final notes = footnotes.where((f) => f.segmentId == segment.id).toList();
      final heading = segment.heading;
      if (heading != null && heading.trim().isNotEmpty && !heading.startsWith('[')) {
        items.add(Align(alignment: AlignmentDirectional.centerStart, child: headingPill(heading)));
      }
      for (final paragraph in layoutSegment(segment.text, notes)) {
        for (final run in paragraph.runs) {
          if (run.isMarker) placed.add(run.footnote!.id);
        }
        items.add(this.paragraph(paragraph));
      }
    }
    final unplaced = footnotes.where((f) => !placed.contains(f.id)).toList();
    if (unplaced.isNotEmpty && withNotes) items.add(notesList(unplaced));
    return items;
  }

  // No `alignment` on the Container: that would stretch the pill to the full width.
  Widget headingPill(String heading) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
    decoration: BoxDecoration(color: t.gold.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
    child: Text(heading, style: TzType.label.copyWith(color: t.goldText)),
  );

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

  Widget paragraph(CommentaryParagraph paragraph) {
    final base = TzType.commentary.scaled(scale).copyWith(color: t.text);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          for (final run in paragraph.runs)
            if (run.isMarker)
              WidgetSpan(
                alignment: PlaceholderAlignment.top,
                child: Semantics(
                  button: true,
                  label: 'حاشية ${run.text}',
                  child: GestureDetector(
                    onTap: () => showFootnote(run.footnote!),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(
                        run.text,
                        style: TzType.caption.scaled(scale).copyWith(color: t.goldText),
                      ),
                    ),
                  ),
                ),
              )
            else
              TextSpan(text: run.text),
        ],
      ),
      textAlign: TextAlign.justify,
    );
  }

  void showFootnote(Footnote note) => showModalBottomSheet<void>(
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
            Text('حاشية ${note.marker ?? ''}', style: TzType.body.copyWith(color: t.goldText)),
            const SizedBox(height: 10),
            Text(note.text, style: TzType.commentary.copyWith(color: t.text)),
          ],
        ),
      ),
    ),
  );

  Widget notesList(List<Footnote> notes) => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
    decoration: BoxDecoration(
      color: t.panel2,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: t.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('الحواشي', style: TzType.label.copyWith(color: t.goldText)),
        for (final n in notes)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${n.marker != null ? '(${n.marker}) ' : ''}${n.text}',
              style: TzType.commentary.scaled(scale).copyWith(color: t.dim),
            ),
          ),
      ],
    ),
  );

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
      child: InkWell(
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

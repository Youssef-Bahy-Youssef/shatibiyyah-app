// lib/ui/shell/index_screen.dart — «الفهرس» (item 3.10, ADR 0012; handoff index).
//
// One list of the 78 chapters under the unwan header and a filter field. Each
// row is a khatam with the chapter's number, its name and its verse range. The
// list opens with the reader's chapter 130 px down; that row's khatam is filled
// and it says «يُتلى الآن» with an equaliser while it is recited, else «الحالي».
// The filter takes part of a name (the search's Arabic normalization: marks and
// letter forms are ignored) or a verse number in either digits. A row opens its
// chapter in the reader.
import 'package:flutter/material.dart';

import '../../data/matn_repository.dart';
import '../../domain/normalizer.dart';
import '../../utils/arabic.dart';
import '../design/components/chapter_row.dart';
import '../design/tokens.g.dart';
import '../design/tz_icon.dart';
import '../design/tz_theme.dart';
import '../reader/reader_controller.dart';
import 'app_shell.dart';
import 'shell_page.dart';

/// The chapters [query] leaves: all for nothing typed, the one holding a verse
/// number, or those whose name contains the words.
List<MatnChapter> filterChapters(List<MatnChapter> chapters, String query) {
  final q = query.trim();
  if (q.isEmpty) return chapters;
  final verse = int.tryParse(normDigits(q));
  if (verse != null) return [for (final c in chapters) if (verse >= c.fromVerse && verse <= c.toVerse) c];
  final words = normalizeMatching(q);
  return [
    for (final c in chapters)
      if (normalizeMatching(c.title).contains(words) || normalizeMatching(c.shortLabel).contains(words)) c,
  ];
}

class IndexScreen extends StatefulWidget {
  final ReaderController reader;
  const IndexScreen({super.key, required this.reader});

  static const filterKey = ValueKey('index-filter');
  static const filterGlyphKey = ValueKey('index-filter-glyph');

  /// How far under the list's top the reader's chapter stands when the index opens.
  static const double currentOffset = 130;

  @override
  State<IndexScreen> createState() => _IndexScreenState();
}

class _IndexScreenState extends State<IndexScreen> {
  final _filter = TextEditingController();
  ScrollController? _scroll;

  MatnRepository get _matn => widget.reader.content.matn;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A row is 64 px, taller only when large text needs it: 12 px of padding, a
    // hairline, and two lines (28 and 16) that grow with the text.
    final extent = (13 + MediaQuery.textScalerOf(context).scale(44)).clamp(64.0, double.infinity);
    final index = _matn.chapters.indexOf(widget.reader.chapter);
    _scroll ??= ScrollController(
        initialScrollOffset: (index * extent - IndexScreen.currentOffset).clamp(0.0, double.infinity));
  }

  @override
  void dispose() {
    _filter.dispose();
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reader = widget.reader;
    return ListenableBuilder(
      listenable: reader,
      builder: (context, _) {
        final c = TzTheme.of(context).colors;
        final chapters = filterChapters(_matn.chapters, _filter.text);
        final filtering = _filter.text.trim().isNotEmpty;
        final current = reader.chapter;
        return ShellPage.topLevel(
          title: 'الفهرس',
          trailing: Text('${chaptersCount(_matn.chapters.length)} · ${versesCount(_matn.lastVerse)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TzType.caption.copyWith(color: c.ink3, fontFeatures: const [FontFeature.tabularFigures()])),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(c),
              Expanded(
                child: chapters.isEmpty
                    ? Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                          child: Text('لا باب بهذا الاسم. جرّب جزءًا من الاسم أو رقم بيت بين ١ و${ar(_matn.lastVerse)}.',
                              textAlign: TextAlign.center, style: TzType.body.copyWith(color: c.ink3)),
                        ),
                      )
                    : ListView.builder(
                        // Unfiltered, the list opens on the reader's chapter; a filter's
                        // results are their own list, from its top.
                        key: ValueKey(filtering),
                        controller: filtering ? null : _scroll,
                        primary: false,
                        padding: EdgeInsets.only(bottom: ShellInset.of(context)),
                        itemCount: chapters.length,
                        itemBuilder: (context, i) => _row(chapters[i], chapters[i].id == current.id, reader.playing),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // v2.css .field: 48 px, 12 px under the gilt rule and 6 px over the list.
  Widget _field(TzColors c) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Container(
        key: IndexScreen.filterKey,
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(TzRadius.control)),
        // The edge is drawn over the box, so the text field inside keeps the full 48 px as its target.
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TzRadius.control),
          border: Border.all(color: c.lineSoft),
        ),
        child: Row(
          children: [
            TzIcon('search', key: IndexScreen.filterGlyphKey, size: 19, color: c.ink3),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                label: 'تصفية الأبواب',
                child: TextField(
                  controller: _filter,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  style: TzType.body.copyWith(color: c.ink),
                  cursorColor: c.lapis,
                  decoration: InputDecoration(
                    // The field's whole height is the target: 24 px of text, 12 above and below.
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: InputBorder.none,
                    hintText: 'اسم الباب أو رقم البيت',
                    hintStyle: TzType.body.copyWith(color: c.ink3),
                  ),
                ),
              ),
            ),
          ],
        ),
      ));

  Widget _row(MatnChapter ch, bool current, bool playing) {
    final status = !current ? null : (playing ? 'يُتلى الآن' : 'الحالي');
    final numbered = ch.orderIndex > 0; // the introduction has no number
    return ChapterRow(
      order: ch.orderIndex,
      number: numbered ? ar(ch.orderIndex) : '',
      name: ch.shortLabel,
      range: '${isolatedRange(ch.fromVerse, ch.toVerse)} · ${versesCount(ch.verseCount)}',
      current: current,
      status: status,
      playing: current && playing,
      semanticLabel: [
        ch.shortLabel,
        if (numbered) 'الباب ${ar(ch.orderIndex)}',
        'الأبيات ${ar(ch.fromVerse)} إلى ${ar(ch.toVerse)}',
        if (current) (playing ? 'يُتلى الآن' : 'الباب الحالي'),
      ].join('، '),
      onTap: () => AppShell.openVerse(context, widget.reader, ch.fromVerse),
    );
  }
}

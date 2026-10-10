// lib/ui/search/search_screen.dart — «البحث» and «الانتقال السريع».
//
// Search (features-v3 search, plan P6 search v2): one field over verses,
// chapters, the user's notes and the three books, with a count per group; a verse,
// chapter or note opens the reader there, a book passage opens that book at its
// verse. Long groups show a page and «عرض المزيد». A number alone is not searched
// for: it offers the verse and the page of that number. Empty, it offers the recent queries, the
// prototype's suggestions and the quick jump.
//
// Quick jump (quick-jump): a page or verse number on an Arabic-Indic keypad, with a
// live preview of the target.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/recent_searches.dart';
import '../../data/user_store.dart' show Note;
import '../../domain/normalizer.dart';
import '../../domain/search.dart';
import '../design/tokens.g.dart';
import '../../utils/arabic.dart';
import '../commentary/commentary_screen.dart';
import '../design/taysir_colors.dart';
import '../design/components/dock.dart' show DockTab;
import '../reader/reader_controller.dart';
import '../reader/split_panel.dart' show kSplitMinWidth;
import '../shell/app_shell.dart';
import '../shell/shell_page.dart' show readingPadding;

const List<String> kSearchSuggestions = ['ورش', 'النقل', 'حمزة', 'بدأت'];

/// Verses shown before «عرض المزيد», and how many more each tap shows.
const int kVersePageSize = 40;

class SearchScreen extends StatefulWidget {
  final ReaderController reader;
  const SearchScreen({super.key, required this.reader});

  static Future<void> open(BuildContext context, ReaderController reader) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SearchScreen(reader: reader)));

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final _searcher = Searcher(widget.reader.content);
  final _field = TextEditingController();
  late final _recent = RecentSearches(widget.reader.viewer.prefs);
  SearchResults _results = SearchResults.empty;
  List<CommentaryHit> _commentary = const [];
  int _commentaryTotal = 0;
  bool _loadingMore = false;
  int _verseLimit = kVersePageSize;
  List<Note> _notes = const [];
  int? _number;
  Timer? _debounce;
  int _generation = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), _run);
    setState(() {});
  }

  Future<void> _run() async {
    final generation = ++_generation;
    // A number alone is a place to go to, not text to look for (digits in the
    // books are mostly Quran verse numbers).
    final number = queryNumber(_field.text);
    final r = number != null
        ? (results: SearchResults.empty, commentaryTotal: 0)
        : await _searcher.search(_field.text);
    if (!mounted || generation != _generation) return; // a newer query is on its way
    final q = r.results.query;
    final personal = widget.reader.personal;
    setState(() {
      _results = r.results;
      _commentary = r.results.commentary;
      _commentaryTotal = r.commentaryTotal;
      _verseLimit = kVersePageSize;
      _loadingMore = false;
      _number = number;
      _notes = q.isEmpty || personal == null ? const [] : notesMatching(personal.notes, q);
    });
  }

  Future<void> _moreCommentary() async {
    if (_loadingMore) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    final more = await _searcher.commentaryPage(_results.query, _commentary.length);
    if (!mounted || generation != _generation) return;
    setState(() {
      _commentary = [..._commentary, ...more];
      _loadingMore = false;
    });
  }

  /// A hit in a book. On a phone: back to the reader, the passage in the sheet
  /// over its verse, in the hit's book (item 3.9). A tablet keeps the pushed
  /// screen: its split panel follows the reader, not a chosen book.
  void _openPassage(CommentaryHit hit) {
    final reader = widget.reader;
    if (MediaQuery.sizeOf(context).width >= kSplitMinWidth) {
      CommentaryScreen.open(context, reader.content, hit.fromVerse, bookId: hit.bookId);
      return;
    }
    reader.setCommentaryBook(hit.bookId);
    (AppShell.of(context) ?? appShell.currentState)?.select(DockTab.matn);
    Navigator.of(context).popUntil((r) => r.isFirst);
    reader.openCommentary(hit.fromVerse);
  }

  void _remember() => _recent.add(_field.text);

  void _setQuery(String q) {
    _field.text = q;
    _run();
  }

  void _openVerse(int verse) {
    _remember();
    AppShell.openVerse(context, widget.reader, verse);
  }

  void _openPage(int page) {
    widget.reader.viewer.setPage(page, true); // browse; playback, if any, carries on
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final typed = normalizedLength(_field.text) >= kMinQueryLength || _number != null;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 12, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'رجوع',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(LucideIcons.chevronRight, size: 21, color: t.text),
                    ),
                    Expanded(child: _searchField(t)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: readingPadding(MediaQuery.sizeOf(context).width, top: 8, bottom: 24),
                  children: typed ? _resultList(t) : _emptyState(t),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchField(TaysirColors t) => Container(
        height: 52,
        padding: const EdgeInsetsDirectional.only(start: 14, end: 4),
        decoration: BoxDecoration(
          color: t.panel2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: t.gold, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.search, size: 19, color: t.muted),
            const SizedBox(width: 6),
            Expanded(
              // Filling a 48 pt box: the field itself is the tap target a screen reader measures.
              child: SizedBox(
                height: 48,
                child: TextField(
                expands: true,
                maxLines: null,
                textAlignVertical: TextAlignVertical.center,
                keyboardType: TextInputType.text, // one line and the search key, despite maxLines: null
                controller: _field,
                autofocus: true,
                onChanged: _onChanged,
                onSubmitted: (_) => _remember(),
                textInputAction: TextInputAction.search,
                style: TzType.chapter.copyWith(color: t.text),
                cursorColor: t.gold,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  hintText: 'ابحث في الأبيات والأبواب والشروح',
                  hintStyle: TzType.chapter.copyWith(color: t.muted),
                ),
              ),
              ),
            ),
            if (_field.text.isNotEmpty)
              IconButton(
                tooltip: 'مسح',
                onPressed: () => _setQuery(''),
                icon: Icon(LucideIcons.x, size: 21, color: t.muted),
              ),
          ],
        ),
      );

  Widget _chip(TaysirColors t, String s) => OutlinedButton(
        onPressed: () => _setQuery(s),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 40),
          side: BorderSide(color: t.line),
          shape: const StadiumBorder(),
        ),
        child: Text(s, style: TzType.chapter.copyWith(color: t.text)),
      );

  List<Widget> _emptyState(TaysirColors t) => [
        if (_recent.all case final recent when recent.isNotEmpty) ...[
          Row(
            children: [
              Expanded(child: Text('بحثت مؤخرًا', style: TzType.caption.copyWith(color: t.muted))),
              TextButton(
                onPressed: () => setState(_recent.clear),
                child: Text('مسح', style: TzType.caption.copyWith(color: t.goldText)),
              ),
            ],
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final s in recent) _chip(t, s)]),
          const SizedBox(height: 18),
        ],
        Text('جرّب: ${kSearchSuggestions.join(' · ')}', style: TzType.caption.copyWith(color: t.muted)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final s in kSearchSuggestions) _chip(t, s)],
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => JumpScreen(reader: widget.reader))),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Row(
              children: [
                Icon(LucideIcons.hash, size: 20, color: t.goldText),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('الانتقال السريع إلى صفحة أو بيت', style: TzType.body.copyWith(color: t.text)),
                      Text('لوحة أرقام هندية', style: TzType.caption.copyWith(color: t.muted)),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronLeft, size: 18, color: t.muted),
              ],
            ),
          ),
        ),
      ];

  List<Widget> _resultList(TaysirColors t) {
    final r = _results;
    final matn = widget.reader.content.matn;
    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(s, style: TzType.caption.copyWith(color: t.muted)),
        );
    Widget card({required Widget child, required VoidCallback onTap}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: t.panel,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: t.line)),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: child),
            ),
          ),
        );
    Widget more(String text, VoidCallback? onTap) => Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: onTap,
            child: Text(text, style: TzType.label.copyWith(color: onTap == null ? t.dim : t.goldText)),
          ),
        );
    final number = _number;
    final numberedVerse = number != null && number >= 1 && number <= matn.lastVerse ? number : null;
    final numberedPage =
        number != null && number >= 1 && number <= widget.reader.content.layout.pageCount ? number : null;
    final nothing = r.isEmpty && _notes.isEmpty && numberedVerse == null && numberedPage == null;
    return [
      if (numberedVerse != null)
        card(
          onTap: () => _openVerse(numberedVerse),
          child: Row(
            children: [
              Icon(LucideIcons.hash, size: 18, color: t.goldText),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('البيت ${ar(numberedVerse)}', style: TzType.label.copyWith(color: t.text)),
                    Text(matn.verse(numberedVerse).firstHemistich,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TzType.verse.copyWith(color: t.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      if (numberedPage != null)
        card(
          onTap: () => _openPage(numberedPage),
          child: Row(
            children: [
              Icon(LucideIcons.bookOpen, size: 18, color: t.goldText),
              const SizedBox(width: 10),
              Text('الصفحة ${ar(numberedPage)}', style: TzType.label.copyWith(color: t.text)),
            ],
          ),
        ),
      if (!r.isEmpty || _notes.isNotEmpty || number == null)
        // «،» between the counts: next to digits a «·» reads as «٠» in Reem Kufi.
        Text(
            'الأبيات ${ar(r.verses.length)}، الأبواب ${ar(r.chapters.length)}، الشروح ${ar(_commentaryTotal)}'
            '${_notes.isEmpty ? '' : '، ملاحظاتك ${ar(_notes.length)}'}',
            style: TzType.caption.copyWith(color: t.muted)),
      if (nothing)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Text('لا نتائج', textAlign: TextAlign.center, style: TzType.label.copyWith(color: t.dim)),
        ),
      if (r.chapters.isNotEmpty) ...[
        label('الأبواب'),
        for (final c in r.chapters)
          card(
            onTap: () => _openVerse(c.fromVerse),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.title, style: TzType.chapter.copyWith(color: t.text)),
                Text('الأبيات ${isolatedRange(c.fromVerse, c.toVerse)}',
                    style: TzType.caption.copyWith(color: t.muted)),
              ],
            ),
          ),
      ],
      if (_notes.isNotEmpty) ...[
        label('ملاحظاتك'),
        for (final note in _notes)
          card(
            onTap: () => _openVerse(note.verse),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('البيت ${ar(note.verse)}', style: TzType.caption.copyWith(color: t.goldText)),
                Text(snippetAround(note.body, r.query),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TzType.commentary.copyWith(color: t.text)),
              ],
            ),
          ),
      ],
      if (r.verses.isNotEmpty) ...[
        label('الأبيات'),
        for (final n in r.verses.take(_verseLimit))
          InkWell(
            onTap: () => _openVerse(n),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(ar(n),
                        textAlign: TextAlign.center,
                        style: TzType.head.copyWith(color: t.goldText)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(matn.verse(n).firstHemistich, style: TzType.verse.copyWith(color: t.text)),
                        Text(matn.verse(n).secondHemistich,
                            textAlign: TextAlign.end, style: TzType.verse.copyWith(color: t.text)),
                        Text(
                          '${matn.chapterOfVerse(n).shortLabel}، ص ${ar(widget.reader.content.layout.pageOfVerse(n))}',
                          style: TzType.caption.copyWith(color: t.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
      if (r.verses.length > _verseLimit)
        more('عرض المزيد (بقي ${ar(r.verses.length - _verseLimit)})',
            () => setState(() => _verseLimit += kVersePageSize)),
      if (_commentary.isNotEmpty) ...[
        label(_commentaryTotal > _commentary.length
            ? 'الشروح (${ar(_commentary.length)} من ${ar(_commentaryTotal)})'
            : 'الشروح'),
        for (final h in _commentary)
          card(
            onTap: () {
              _remember();
              _openPassage(h);
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(h.bookTitle, style: TzType.caption.copyWith(color: t.goldText)),
                    const SizedBox(width: 8),
                    Text(
                      h.fromVerse == h.toVerse
                          ? 'البيت ${ar(h.fromVerse)}'
                          : 'الأبيات ${isolatedRange(h.fromVerse, h.toVerse)}',
                      style: TzType.caption.copyWith(color: t.muted),
                    ),
                  ],
                ),
                Text(h.snippet, style: TzType.commentary.copyWith(color: t.text)),
              ],
            ),
          ),
        if (_commentaryTotal > _commentary.length)
          more(_loadingMore ? 'جارٍ التحميل…' : 'عرض المزيد (بقي ${ar(_commentaryTotal - _commentary.length)})',
              _loadingMore ? null : _moreCommentary),
      ],
    ];
  }
}

/// Length of [text] once normalized (a lone letter or mark is not a query yet).
int normalizedLength(String text) => normalizeMatching(text).length;

/// «الانتقال السريع»: a page or verse number on an Arabic-Indic keypad.
class JumpScreen extends StatefulWidget {
  final ReaderController reader;
  const JumpScreen({super.key, required this.reader});

  @override
  State<JumpScreen> createState() => _JumpScreenState();
}

class _JumpScreenState extends State<JumpScreen> {
  bool _verse = true; // «بيت» or «صفحة»
  late String _digits = '${widget.reader.verse}';

  int get _max => _verse ? widget.reader.content.matn.lastVerse : widget.reader.content.layout.pageCount;
  int? get _target {
    final n = int.tryParse(_digits);
    return n != null && n >= 1 && n <= _max ? n : null;
  }

  void _key(String k) {
    setState(() {
      if (k == 'del') {
        _digits = _digits.isEmpty ? '' : _digits.substring(0, _digits.length - 1);
      } else if (_digits.length < '$_max'.length) {
        _digits = _digits == '0' ? k : '$_digits$k';
      }
    });
  }

  void _go() {
    final n = _target;
    if (n == null) return;
    final reader = widget.reader;
    if (_verse) {
      reader.tapVerse(n);
    } else {
      reader.viewer.setPage(n, true); // browse to the page; playback, if any, carries on
    }
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final content = widget.reader.content;
    final n = _target;
    final String previewA, previewB;
    if (n == null) {
      previewA = 'من ١ إلى ${ar(_max)}';
      previewB = '';
    } else if (_verse) {
      previewA = content.matn.verse(n).firstHemistich;
      previewB = content.matn.verse(n).secondHemistich;
    } else {
      final verses = content.layout.versesOnPage(n);
      previewA = 'صفحة المخطوط ${ar(n)}';
      previewB = verses.isEmpty
          ? ''
          : '${content.matn.chapterOfVerse(verses.first).shortLabel}، الأبيات ${isolatedRange(verses.first, verses.last)}';
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 56,
                child: Row(
                  children: [
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'رجوع',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(LucideIcons.chevronRight, size: 21, color: t.text),
                    ),
                    Expanded(
                      child: Text('الانتقال السريع',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TzType.display.copyWith(color: t.text)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (final (isVerse, l) in [(false, 'صفحة'), (true, 'بيت')])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: SizedBox(
                              width: double.infinity,
                              child: Text(l,
                                  textAlign: TextAlign.center,
                                  style: TzType.label.copyWith(color: _verse == isVerse ? t.onGold : t.text)),
                            ),
                            selected: _verse == isVerse,
                            showCheckmark: false,
                            selectedColor: t.gold,
                            backgroundColor: t.panel2,
                            side: BorderSide(color: t.line),
                            shape: const StadiumBorder(),
                            onSelected: (_) => setState(() {
                              _verse = isVerse;
                              _digits = isVerse ? '${widget.reader.verse}' : '${widget.reader.page}';
                            }),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${_digits.isEmpty ? '—' : ar(int.parse(_digits))} من ${ar(_max)}',
                textAlign: TextAlign.center,
                style: TzType.display.copyWith(color: t.goldText),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                // At least two lines tall, so the keypad does not jump as the preview changes.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 88),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(previewA,
                          textAlign: _verse && n != null ? TextAlign.start : TextAlign.center,
                          style: TzType.verse.copyWith(color: t.dim)),
                      if (previewB.isNotEmpty)
                        Text(previewB,
                            textAlign: _verse ? TextAlign.end : TextAlign.center,
                            style: _verse
                                ? TzType.verse.copyWith(color: t.dim)
                                : TzType.label.copyWith(color: t.muted)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final k in ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'del', '0', 'go'])
                      _keyButton(t, k, n != null),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keyButton(TaysirColors t, String k, bool canGo) {
    final go = k == 'go';
    return Material(
      color: go ? (canGo ? t.gold : t.line) : t.panel2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: go ? BorderSide.none : BorderSide(color: t.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: go ? (canGo ? _go : null) : () => _key(k),
        child: Center(
          child: k == 'del'
              ? Icon(LucideIcons.delete, size: 24, color: t.text, semanticLabel: 'حذف')
              : go
                  ? Icon(LucideIcons.arrowLeft, size: 24, color: t.onGold, semanticLabel: 'انتقال')
                  : Text(ar(int.parse(k)), style: TzType.hero.copyWith(color: t.text)),
        ),
      ),
    );
  }
}

// lib/ui/search/search_screen.dart — «البحث» and «الانتقال السريع».
//
// Search (features-v3 search): one field over verses, chapters and the three
// books, with a count per group; a verse or chapter opens the reader there, a
// book passage opens that book at its verse. Empty, it offers the prototype's
// suggestions and the quick jump.
//
// Quick jump (quick-jump): a page or verse number on an Arabic-Indic keypad, with a
// live preview of the target.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../domain/normalizer.dart';
import '../../domain/search.dart';
import '../../theme.dart' show kufi, naskh;
import '../../utils/arabic.dart';
import '../commentary/commentary_screen.dart';
import '../design/taysir_colors.dart';
import '../reader/reader_controller.dart';

const List<String> kSearchSuggestions = ['ورش', 'النقل', 'حمزة', 'بدأت'];

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
  SearchResults _results = SearchResults.empty;
  int _commentaryTotal = 0;
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
    final r = await _searcher.search(_field.text);
    if (!mounted || generation != _generation) return; // a newer query is on its way
    setState(() {
      _results = r.results;
      _commentaryTotal = r.commentaryTotal;
    });
  }

  void _setQuery(String q) {
    _field.text = q;
    _run();
  }

  void _openVerse(int verse) {
    widget.reader.tapVerse(verse);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final typed = normalizedLength(_field.text) >= kMinQueryLength;
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
                padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
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
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
              child: TextField(
                controller: _field,
                autofocus: true,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                style: naskh(size: 18, color: t.text),
                cursorColor: t.gold,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  hintText: 'ابحث في الأبيات والأبواب والشروح',
                  hintStyle: naskh(size: 17, color: t.muted),
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

  List<Widget> _emptyState(TaysirColors t) => [
        Text('جرّب: ${kSearchSuggestions.join(' · ')}', style: kufi(size: 12.5, weight: 400, color: t.muted)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in kSearchSuggestions)
              OutlinedButton(
                onPressed: () => _setQuery(s),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  side: BorderSide(color: t.line),
                  shape: const StadiumBorder(),
                ),
                child: Text(s, style: naskh(size: 16, color: t.text)),
              ),
          ],
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
                      Text('الانتقال السريع إلى صفحة أو بيت', style: kufi(size: 15, weight: 400, color: t.text)),
                      Text('لوحة أرقام هندية', style: kufi(size: 12.5, weight: 400, color: t.muted)),
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
          child: Text(s, style: kufi(size: 12.5, weight: 400, color: t.muted)),
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
    return [
      // «،» between the counts: next to digits a «·» reads as «٠» in Reem Kufi.
      Text('الأبيات ${ar(r.verses.length)}، الأبواب ${ar(r.chapters.length)}، الشروح ${ar(_commentaryTotal)}',
          style: kufi(size: 12.5, weight: 400, color: t.muted)),
      if (r.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Text('لا نتائج', textAlign: TextAlign.center, style: kufi(size: 14, weight: 400, color: t.dim)),
        ),
      if (r.chapters.isNotEmpty) ...[
        label('الأبواب'),
        for (final c in r.chapters)
          card(
            onTap: () => _openVerse(c.fromVerse),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.title, style: naskh(size: 17, weight: FontWeight.w700, color: t.text, height: 1.7)),
                Text('الأبيات ${isolatedRange(c.fromVerse, c.toVerse)}',
                    style: kufi(size: 12, weight: 400, color: t.muted)),
              ],
            ),
          ),
      ],
      if (r.verses.isNotEmpty) ...[
        label('الأبيات'),
        for (final n in r.verses)
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
                        style: naskh(size: 16, weight: FontWeight.w700, color: t.goldText, height: 1.6)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(matn.verse(n).firstHemistich, style: naskh(size: 18, color: t.text, height: 1.6)),
                        Text(matn.verse(n).secondHemistich,
                            textAlign: TextAlign.left, style: naskh(size: 18, color: t.text, height: 1.6)),
                        Text(
                          '${matn.chapterOfVerse(n).shortLabel}، ص ${ar(widget.reader.content.layout.pageOfVerse(n))}',
                          style: kufi(size: 12, weight: 400, color: t.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
      if (r.commentary.isNotEmpty) ...[
        label(_commentaryTotal > r.commentary.length
            ? 'الشروح (أول ${ar(r.commentary.length)} من ${ar(_commentaryTotal)})'
            : 'الشروح'),
        for (final h in r.commentary)
          card(
            onTap: () => CommentaryScreen.open(context, widget.reader.content, h.fromVerse, bookId: h.bookId),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(h.bookTitle, style: kufi(size: 12, weight: 600, color: t.goldText)),
                    const SizedBox(width: 8),
                    Text(
                      h.fromVerse == h.toVerse
                          ? 'البيت ${ar(h.fromVerse)}'
                          : 'الأبيات ${isolatedRange(h.fromVerse, h.toVerse)}',
                      style: kufi(size: 12, weight: 400, color: t.muted),
                    ),
                  ],
                ),
                Text(h.snippet, style: naskh(size: 16.5, color: t.text, height: 1.75)),
              ],
            ),
          ),
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
                    Text('الانتقال السريع', style: kufi(size: 20, weight: 600, color: t.text)),
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
                                  style: kufi(size: 14, weight: 600, color: _verse == isVerse ? t.onGold : t.text)),
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
                style: naskh(size: 34, weight: FontWeight.w700, color: t.goldText),
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
                          textAlign: _verse && n != null ? TextAlign.right : TextAlign.center,
                          style: naskh(size: 18, color: t.dim, height: 1.6)),
                      if (previewB.isNotEmpty)
                        Text(previewB,
                            textAlign: _verse ? TextAlign.left : TextAlign.center,
                            style: _verse
                                ? naskh(size: 18, color: t.dim, height: 1.6)
                                : kufi(size: 13, weight: 400, color: t.muted)),
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
                  : Text(ar(int.parse(k)), style: naskh(size: 26, weight: FontWeight.w700, color: t.text)),
        ),
      ),
    );
  }
}

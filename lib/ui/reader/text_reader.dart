// lib/ui/reader/text_reader.dart — «العرض النصي»: the verses as typeset text.
//
// features-v3 text-mode-reader: the chapter's verses, first hemistich right and
// second left, stacked on phones, the current verse highlighted, font 0.75×–2×.
// It fills the same zone as the page, between the top bar and the player. It
// follows the reader's verse like the page does; the chapter buttons at the end
// browse other chapters until the verse moves again. A tap moves the reader to a
// verse; a double tap (or a long press, as on the page) opens the verse menu.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/matn_repository.dart';
import '../../theme.dart' show kufi, naskh;
import '../../utils/arabic.dart';
import '../design/taysir_colors.dart';
import 'reader_controller.dart';

const double _kScaleStep = 0.25;

class TextReader extends StatefulWidget {
  final ReaderController reader;
  const TextReader({super.key, required this.reader});

  @override
  State<TextReader> createState() => TextReaderState();
}

class TextReaderState extends State<TextReader> {
  final Map<int, GlobalKey> _rows = {};
  final _scroll = ScrollController();

  /// The chapter the student browsed to, or null while following the reader's verse.
  int? _browsed;
  late int _followedVerse;

  ReaderController get _reader => widget.reader;

  @override
  void initState() {
    super.initState();
    _followedVerse = _reader.verse;
    _reader.addListener(_onReader);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(_reader.verse, animate: false));
  }

  @override
  void dispose() {
    _reader.removeListener(_onReader);
    _scroll.dispose();
    super.dispose();
  }

  void _onReader() {
    if (_reader.verse == _followedVerse) return;
    _followedVerse = _reader.verse;
    setState(() => _browsed = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(_reader.verse, animate: true));
  }

  /// Scrolls [verse]'s row into view, unless it is already fully on screen.
  void _reveal(int verse, {required bool animate}) {
    final context = _rows[verse]?.currentContext;
    if (context == null || !mounted) return;
    final row = rowRect(verse);
    final viewport = this.context.findRenderObject() as RenderBox?;
    if (row != null && viewport != null && viewport.hasSize) {
      final view = viewport.localToGlobal(Offset.zero) & viewport.size;
      if (row.top >= view.top && row.bottom <= view.bottom) return;
    }
    Scrollable.ensureVisible(
      context,
      alignment: 0.3,
      duration: animate ? const Duration(milliseconds: 250) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  /// Where [verse]'s row is on screen, for anchoring the verse menu.
  Rect? rowRect(int verse) {
    final box = _rows[verse]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  int get _chapterIndex {
    final matn = _reader.content.matn;
    return _browsed ?? matn.chapters.indexOf(matn.chapterOfVerse(_reader.verse));
  }

  void _browse(int index) {
    setState(() => _browsed = index);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final matn = _reader.content.matn;
    final index = _chapterIndex;
    final chapter = matn.chapters[index];
    final scale = _reader.textScale;
    // A chapter has at most ~100 verses: build every row, so any of them can be scrolled to.
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(t, matn, chapter, scale),
          for (var n = chapter.fromVerse; n <= chapter.toVerse; n++) _row(t, matn.verse(n), scale),
          _footer(t, matn, index),
        ],
      ),
    );
  }

  Widget _header(TaysirColors t, MatnRepository matn, MatnChapter chapter, double scale) {
    // The introduction is not a numbered chapter, and its title «مقدمة» would repeat the part's name.
    final intro = chapter.orderIndex == 0;
    final where = intro ? matn.partOf(chapter).title : 'الباب ${ar(chapter.orderIndex)}';
    final title = intro ? chapter.shortLabel : chapter.title;
    Widget step(String label, String tip, double to) {
      final enabled = to >= 0.75 && to <= 2;
      return Semantics(
        button: true,
        label: tip,
        child: InkWell(
          onTap: enabled ? () => _reader.setTextScale(to) : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 44,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: t.line),
            ),
            child: Text(label, style: naskh(size: 17, color: enabled ? t.text : t.muted)),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
      child: Column(
        children: [
          Text('$where · ${versesCount(chapter.verseCount)}', style: kufi(size: 12, weight: 400, color: t.muted)),
          Text(title,
              textAlign: TextAlign.center,
              style: naskh(size: 22, weight: FontWeight.w700, color: t.goldText, height: 1.7)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              step('أ−', 'تصغير الخط', scale - _kScaleStep),
              SizedBox(
                width: 52,
                child: Text('${ar(scale)}×',
                    textAlign: TextAlign.center, style: kufi(size: 13, weight: 400, color: t.dim)),
              ),
              step('أ+', 'تكبير الخط', scale + _kScaleStep),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(TaysirColors t, MatnVerse v, double scale) {
    final on = v.number == _reader.verse;
    final badge = 36 * scale.clamp(0.75, 1.5);
    final line = naskh(size: 20 * scale, color: t.text, height: 1.65);
    final key = _rows.putIfAbsent(v.number, GlobalKey.new);
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: () => _reader.tapVerse(v.number),
      onDoubleTap: () => _reader.openMenu(v.number),
      onLongPress: () => _reader.openMenu(v.number),
      child: Semantics(
        label: 'البيت ${ar(v.number)}',
        selected: on,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: on ? t.gold.withValues(alpha: 0.16) : null,
            borderRadius: BorderRadius.circular(16),
            // The start-side bar of the prototype's `inset -3px 0 0` (the right edge in RTL).
            border: on ? Border(right: BorderSide(color: t.gold, width: 3)) : null,
          ),
          child: Row(
            children: [
              Container(
                width: badge,
                height: badge,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: on ? t.gold : t.line, width: 1.5),
                ),
                child: Text(ar(v.number),
                    style: naskh(size: 15 * scale.clamp(0.75, 1.5), weight: FontWeight.w700, color: t.goldText)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(v.firstHemistich, textAlign: TextAlign.right, style: line),
                    Padding(
                      padding: EdgeInsets.only(right: scale > 1.4 ? 24 : 0),
                      child: Text(v.secondHemistich, textAlign: TextAlign.left, style: line),
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

  Widget _footer(TaysirColors t, MatnRepository matn, int index) {
    Widget go(String label, IconData icon, int to, {required bool iconFirst}) {
      final enabled = to >= 0 && to < matn.chapters.length;
      final children = [
        Icon(icon, size: 18, color: enabled ? t.text : t.muted),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: kufi(size: 13.5, weight: 500, color: enabled ? t.text : t.muted)),
        ),
      ];
      return Expanded(
        child: OutlinedButton(
          onPressed: enabled ? () => _browse(to) : null,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            side: BorderSide(color: t.line),
            shape: const StadiumBorder(),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: iconFirst ? children : children.reversed.toList(),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 16),
      child: Column(
        children: [
          Row(
            children: [
              go('الباب السابق', LucideIcons.chevronRight, index - 1, iconFirst: true),
              const SizedBox(width: 10),
              go('الباب التالي', LucideIcons.chevronLeft, index + 1, iconFirst: false),
            ],
          ),
          const SizedBox(height: 10),
          Text('نقرتان على بيت تفتحان قائمته',
              textAlign: TextAlign.center, style: kufi(size: 12, weight: 400, color: t.muted)),
        ],
      ),
    );
  }
}

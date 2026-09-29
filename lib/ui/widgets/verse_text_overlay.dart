// lib/ui/widgets/verse_text_overlay.dart — unified verse/chapter search.
// Ported from app.js (runSearchOn / buildResultRow / buildChapterResultRow / appendHighlighted)
// + index.html (#vsearch desktop bar, #search-overlay mobile) + style.css. Diacritic-
// insensitive; chapters group (الأبواب) first, then verses (الأبيات), match highlighted.
import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../services/verse_text.dart';
import '../../theme.dart';
import '../../utils/arabic.dart';

// ported from app.js: appendHighlighted(container, display, normQuery)
List<InlineSpan> _highlight(String display, String normQuery, TextStyle base) {
  if (normQuery.isEmpty) return [TextSpan(text: display)];
  final nm = normalizeWithMap(display);
  final pos = nm.norm.indexOf(normQuery);
  if (pos < 0) return [TextSpan(text: display)];
  final start = nm.map[pos];
  final lastIdx = nm.map[pos + normQuery.length - 1];
  int end = lastIdx + 1;
  while (end < display.length && isMark(display[end])) {
    end++;
  }
  final markPaint = Paint()..color = const Color(0x40C8860A); // rgba(200,134,10,.25)
  return [
    TextSpan(text: display.substring(0, start)),
    TextSpan(text: display.substring(start, end), style: base.copyWith(background: markPaint)),
    TextSpan(text: display.substring(end)),
  ];
}

/// Shared results renderer for both the desktop bar and the mobile overlay.
class SearchResultsList extends StatelessWidget {
  final AppController app;
  final SearchResults results;
  final VoidCallback onPick;
  const SearchResultsList(
      {super.key, required this.app, required this.results, required this.onPick});

  @override
  Widget build(BuildContext context) {
    if (results.normQuery.isEmpty) return const SizedBox.shrink();
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('لا توجد نتائج',
              style: ui(size: 13.6, color: C.muted)),
        ),
      );
    }
    final children = <Widget>[];
    if (results.chapters.isNotEmpty) {
      children.add(_group('الأبواب'));
      for (final idx in results.chapters) {
        children.add(_chapterRow(idx));
      }
    }
    if (results.verses.isNotEmpty) {
      children.add(_group('الأبيات'));
      for (final v in results.verses) {
        children.add(_verseRow(v));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _group(String t) => Container(
        margin: const EdgeInsets.only(top: 2),
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: C.lineSoft))),
        alignment: Alignment.centerRight,
        child: Text(t,
            style: ui(size: 11.52, weight: FontWeight.w700, color: C.gold)),
      );

  Widget _chapterRow(int idx) {
    final c = app.data.chapters[idx];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: () {
          onPick();
          app.searchPickChapter(idx);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            color: C.panel2,
            border: Border.all(color: C.line),
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Row(
            children: [
              const Text('📖', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: naskh(size: 17.6, color: C.parch)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Text('الأبيات ${ar(c.startVerse)}–${ar(c.endVerse)}',
                          style: ui(size: 11.2, color: C.muted, tabular: true)),
                      const SizedBox(width: 10),
                      Text('${ar(c.verseCount)} بيت',
                          style: ui(size: 11.2, color: C.muted, tabular: true)),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _verseRow(IndexEntry v) {
    final idx = app.data.chapterIndexForVerse(v.id);
    final chap = idx >= 0 ? app.data.chapters[idx].name : '';
    final page = app.data.pageOfVerse(v.id);
    final base = naskh(size: 16.8, color: C.parch);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: () {
          onPick();
          app.searchPickVerse(v.id);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: C.panel2,
            border: Border.all(color: C.line),
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Text(ar(v.id),
                    style: ui(
                        size: 13.12,
                        weight: FontWeight.w700,
                        color: C.goldBright,
                        tabular: true)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(chap,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ui(size: 11.2, color: C.parchDim)),
                ),
                if (page != null)
                  Text('صـ ${ar(page)}',
                      style: ui(size: 11.2, color: C.muted, tabular: true)),
              ]),
              const SizedBox(height: 3),
              Text.rich(
                TextSpan(style: base, children: _highlight(v.sadr, results.normQuery, base)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen verse search overlay (mobile) — .search-overlay.
class SearchOverlay extends StatefulWidget {
  final AppController app;
  const SearchOverlay({super.key, required this.app});
  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  SearchResults _results = const SearchResults([], [], '');

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _run() => setState(() => _results = widget.app.runSearch(_ctrl.text));

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.app,
      builder: (context, _) {
        final open = widget.app.searchOverlayOpen;
        if (open && !_focus.hasFocus) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && widget.app.searchOverlayOpen) _focus.requestFocus();
          });
        }
        if (!open && _ctrl.text.isNotEmpty) {
          _ctrl.clear();
          _results = const SearchResults([], [], '');
        }
        return IgnorePointer(
          ignoring: !open,
          child: AnimatedOpacity(
            opacity: open ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              color: C.ink2,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: widget.app.closeSearchOverlay,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              child: Text('✕',
                                  style: TextStyle(color: C.gold, fontSize: 20)),
                            ),
                          ),
                          Expanded(
                            child: Text('البحث في الأبيات',
                                textAlign: TextAlign.center,
                                style: kufi(
                                    size: 16, weight: 600, color: C.gold)),
                          ),
                          const SizedBox(width: 40),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focus,
                        onChanged: (_) => _run(),
                        textDirection: TextDirection.rtl,
                        style: naskh(size: 18, color: C.parch),
                        decoration: InputDecoration(
                          hintText: 'ابحث في الأبيات…',
                          hintStyle: naskh(size: 18, color: C.muted2),
                          filled: true,
                          fillColor: C.panel2,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: C.gold, width: 1.5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: C.gold, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: SearchResultsList(
                          app: widget.app,
                          results: _results,
                          onPick: widget.app.closeSearchOverlay,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Desktop inline search bar (.vsearch) + its results.
class VSearchBar extends StatefulWidget {
  final AppController app;
  const VSearchBar({super.key, required this.app});
  @override
  State<VSearchBar> createState() => _VSearchBarState();
}

class _VSearchBarState extends State<VSearchBar> {
  final _ctrl = TextEditingController();
  SearchResults _results = const SearchResults([], [], '');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _clear() {
    _ctrl.clear();
    setState(() => _results = const SearchResults([], [], ''));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: C.panel2,
            border: Border.all(color: C.line),
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, size: 18, color: C.muted),
              const SizedBox(width: 9),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  onChanged: (_) =>
                      setState(() => _results = widget.app.runSearch(_ctrl.text)),
                  textDirection: TextDirection.rtl,
                  style: naskh(size: 17.6, color: C.parch),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'ابحث في الأبيات…',
                    hintStyle: naskh(size: 17.6, color: C.muted2),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_results.normQuery.isNotEmpty) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: SingleChildScrollView(
              child: SearchResultsList(
                  app: widget.app, results: _results, onPick: _clear),
            ),
          ),
        ],
      ],
    );
  }
}

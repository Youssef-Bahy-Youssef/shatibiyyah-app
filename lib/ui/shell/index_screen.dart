// lib/ui/shell/index_screen.dart — «الفهرس» (features-v3 structured-index).
//
// The four parts as chips, a card for the chosen part, then every chapter of the
// part as its own card: number badge (a tick once every verse has been listened
// to), short label, «الحالي» on the reader's chapter, the verse range and a
// listening bar. The prototype's memorisation bar is left out (dropped from v2).
// A card opens the reader at the chapter's first verse.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/matn_repository.dart';
import '../../theme.dart' show kufi, naskh;
import '../../utils/arabic.dart';
import '../design/taysir_colors.dart';
import '../reader/reader_controller.dart';
import 'shell_page.dart';

/// Wraps a number range so it keeps its order inside Arabic text (FSI … PDI). Next to
/// numbers the separator is «،»: in Reem Kufi a «·» there reads as the digit «٠».
String isolatedRange(int from, int to) => '\u2068${ar(from)}–${ar(to)}\u2069';

class IndexScreen extends StatefulWidget {
  final ReaderController reader;
  const IndexScreen({super.key, required this.reader});

  @override
  State<IndexScreen> createState() => _IndexScreenState();
}

class _IndexScreenState extends State<IndexScreen> {
  late int _part;
  Set<int> _listened = const {};

  MatnRepository get _matn => widget.reader.content.matn;

  @override
  void initState() {
    super.initState();
    final current = _matn.chapterOfVerse(widget.reader.verse);
    _part = _matn.parts.indexWhere((p) => p.id == current.partId);
    widget.reader.user?.listenedVerses().then((v) {
      if (mounted) setState(() => _listened = v);
    });
  }

  void _open(MatnChapter c) {
    widget.reader.tapVerse(c.fromVerse);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final part = _matn.parts[_part];
    final chapters = _matn.chapters.where((c) => c.partId == part.id).toList();
    final current = _matn.chapterOfVerse(widget.reader.verse);
    return ShellPage(
      title: 'الفهرس',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _matn.parts.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) =>
                  _chip(t, _matn.parts[i].title, i == _part, () => setState(() => _part = i)),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: t.raised,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: t.goldDeep),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(part.title, style: kufi(size: 19, weight: 600, color: t.goldBright)),
                    ),
                    Text(
                      'الأبيات ${isolatedRange(part.fromVerse, part.toVerse)}، ${chaptersCount(chapters.length)}',
                      style: kufi(size: 12.5, weight: 400, color: t.dim),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 18,
                      height: 6,
                      decoration: BoxDecoration(color: t.gold, borderRadius: BorderRadius.circular(999)),
                    ),
                    const SizedBox(width: 6),
                    Text('سماع', style: kufi(size: 12, weight: 400, color: t.dim)),
                  ],
                ),
              ],
            ),
          ),
          for (final c in chapters) ...[const SizedBox(height: 10), _card(t, c, c.id == current.id)],
        ],
      ),
    );
  }

  Widget _chip(TaysirColors t, String label, bool on, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(999),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? t.gold : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: on ? t.gold : t.line),
      ),
      child: Text(
        label,
        style: kufi(size: 14, weight: on ? 600 : 400, color: on ? t.onGold : t.text),
      ),
    ),
  );

  Widget _card(TaysirColors t, MatnChapter c, bool current) {
    final heard = [for (var v = c.fromVerse; v <= c.toVerse; v++) v].where(_listened.contains).length;
    final fraction = heard / c.verseCount;
    final done = heard == c.verseCount;
    final pct = (fraction * 100).round();
    final Color badgeBg = done ? t.teal : (current ? t.gold : t.panel2);
    return Semantics(
      button: true,
      label: '${c.shortLabel}، ${current ? 'الباب الحالي، ' : ''}سماع ${ar(pct)} بالمئة',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _open(c),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: current ? t.gold.withValues(alpha: 0.10) : t.panel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: current ? t.goldDeep : t.line),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: badgeBg,
                  border: done || current ? null : Border.all(color: t.line),
                ),
                child: done
                    ? Icon(LucideIcons.check, size: 18, color: t.bg)
                    : c.orderIndex ==
                          0 // the introduction has no chapter number
                    ? Icon(LucideIcons.bookOpen, size: 18, color: current ? t.onGold : t.goldBright)
                    : Text(
                        ar(c.orderIndex),
                        style: naskh(
                          size: 15,
                          weight: FontWeight.w700,
                          color: current ? t.onGold : t.goldBright,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.shortLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: naskh(size: 17, weight: FontWeight.w700, color: t.text, height: 1.75),
                          ),
                        ),
                        if (current)
                          Container(
                            height: 22,
                            margin: const EdgeInsetsDirectional.only(start: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: t.gold,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('الحالي', style: kufi(size: 11, weight: 600, color: t.onGold)),
                          ),
                      ],
                    ),
                    Text(
                      '${isolatedRange(c.fromVerse, c.toVerse)}، ${versesCount(c.verseCount)}',
                      style: kufi(size: 12, weight: 400, color: t.muted),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        SizedBox(
                          width: 30,
                          child: Text('سماع', style: kufi(size: 11, weight: 400, color: t.muted)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          // The prototype fills its bars left to right (`direction: ltr`).
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: fraction,
                                minHeight: 6,
                                color: t.gold,
                                backgroundColor: t.line,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 36,
                          child: Text(
                            '${ar(pct)}٪',
                            textAlign: TextAlign.left,
                            style: kufi(size: 11, weight: 400, color: t.dim),
                          ),
                        ),
                      ],
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
}

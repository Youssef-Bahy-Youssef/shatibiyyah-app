// lib/ui/shell/index_screen.dart — «الفهرس» (features-v3 structured-index).
//
// The four parts as chips, a card for the chosen part, then every chapter of the
// part as its own card: number badge, short label, «الحالي» on the reader's
// chapter and the verse range. The prototype's memorisation and listening bars are
// left out (dropped from v2; ADR 0008). A card opens the reader at the chapter's
// first verse.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/matn_repository.dart';
import '../design/tokens.g.dart';
import '../../utils/arabic.dart';
import '../design/taysir_colors.dart';
import '../design/components/dock.dart' show DockTab;
import '../reader/reader_controller.dart';
import 'app_shell.dart';
import 'shell_page.dart';

class IndexScreen extends StatefulWidget {
  final ReaderController reader;
  const IndexScreen({super.key, required this.reader});

  @override
  State<IndexScreen> createState() => _IndexScreenState();
}

class _IndexScreenState extends State<IndexScreen> {
  late int _part;

  MatnRepository get _matn => widget.reader.content.matn;

  @override
  void initState() {
    super.initState();
    final current = _matn.chapterOfVerse(widget.reader.verse);
    _part = _matn.parts.indexWhere((p) => p.id == current.partId);
  }

  void _open(MatnChapter c) {
    widget.reader.tapVerse(c.fromVerse);
    AppShell.of(context)?.select(DockTab.matn);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final part = _matn.parts[_part];
    final chapters = _matn.chapters.where((c) => c.partId == part.id).toList();
    final current = _matn.chapterOfVerse(widget.reader.verse);
    return ShellPage.topLevel(
      title: 'الفهرس',
      trailing: Text('${chaptersCount(_matn.chapters.length)} · ${versesCount(_matn.lastVerse)}',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: TzType.caption.copyWith(color: t.muted)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(14, 8, 14, 24 + ShellInset.of(context)),
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
                // A Wrap across the full width: the range moves under the title when
                // large text leaves no room.
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 12,
                    children: [
                      Text(part.title, style: TzType.title.copyWith(color: t.goldBright)),
                      Text(
                        'الأبيات ${isolatedRange(part.fromVerse, part.toVerse)}، ${chaptersCount(chapters.length)}',
                        style: TzType.caption.copyWith(color: t.dim),
                      ),
                    ],
                  ),
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
        style: TzType.label.copyWith(color: on ? t.onGold : t.text),
      ),
    ),
  );

  Widget _card(TaysirColors t, MatnChapter c, bool current) {
    return Semantics(
      button: true,
      label: current ? '${c.shortLabel}، الباب الحالي' : c.shortLabel,
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
                  color: current ? t.gold : t.panel2,
                  border: current ? null : Border.all(color: t.line),
                ),
                child: c.orderIndex ==
                          0 // the introduction has no chapter number
                    ? Icon(LucideIcons.bookOpen, size: 18, color: current ? t.onGold : t.goldBright)
                    : Text(
                        ar(c.orderIndex),
                        style: TzType.head.copyWith(color: current ? t.onGold : t.goldBright),
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
                            style: TzType.chapter.copyWith(color: t.text),
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
                            child: Text('الحالي', style: TzType.caption.copyWith(color: t.onGold)),
                          ),
                      ],
                    ),
                    Text(
                      '${isolatedRange(c.fromVerse, c.toVerse)}، ${versesCount(c.verseCount)}',
                      style: TzType.caption.copyWith(color: t.muted),
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

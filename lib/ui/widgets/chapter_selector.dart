// lib/ui/widgets/chapter_selector.dart — the chapter list (.chapter-list / .chap-item).
// Ported from app.js buildChapterList() + style.css. Each row: number badge, name, meta
// (verses · count · page range), a per-chapter progress bar, and a "done" dot at ≥0.999.
import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../theme.dart';
import '../../utils/arabic.dart';

class ChapterSelector extends StatelessWidget {
  final AppController app;
  final ScrollController? scrollController;
  const ChapterSelector({super.key, required this.app, this.scrollController});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final data = app.data;
        final activeIdx =
            app.audio.mode == 'chapter' ? app.audio.chapterIdx : -1;
        return ListView.separated(
          controller: scrollController,
          padding: const EdgeInsets.all(2),
          itemCount: data.chapters.length,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, i) {
            final c = data.chapters[i];
            final pr = data.pageRangeOfChapter(i);
            final pages = pr == null
                ? '—'
                : (pr[0] == pr[1]
                    ? ar(pr[0])
                    : '${ar(pr[0])}–${ar(pr[1])}');
            final prog = (app.chapterProgress[i] ?? 0).clamp(0.0, 1.0);
            final done = prog >= 0.999;
            final active = i == activeIdx;
            return GestureDetector(
              onTap: () => app.selectChapter(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                decoration: BoxDecoration(
                  color: active ? const Color(0x1AFFAB2E) : C.panel2,
                  border: Border.all(color: active ? C.gold : C.line),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Row(
                  children: [
                    // chap-num badge
                    Container(
                      constraints: const BoxConstraints(minWidth: 30),
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: active
                            ? const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [C.goldBright, C.gold])
                            : null,
                        color: active ? null : const Color(0x1AFFAB2E),
                        border: Border.all(color: active ? Colors.transparent : C.line),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(ar(i + 1),
                          style: ui(
                              size: 13.76,
                              color: active ? C.onGold : C.goldBright,
                              tabular: true)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: naskh(
                                  size: 16.96,
                                  weight: FontWeight.w600,
                                  color: C.parch,
                                  height: 1.25)),
                          const SizedBox(height: 3),
                          Text(
                              'الأبيات ${ar(c.startVerse)}–${ar(c.endVerse)} · ${ar(c.verseCount)} بيت · ص $pages',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ui(size: 10.88, color: C.muted, tabular: true)),
                          const SizedBox(height: 4),
                          // chap-prog
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              height: 3,
                              color: C.lineSoft,
                              child: FractionallySizedBox(
                                alignment: AlignmentDirectional.centerStart,
                                widthFactor: prog,
                                child: Container(color: C.gold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // chap-done dot
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: done ? 1 : 0,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: C.teal,
                          boxShadow: [
                            BoxShadow(color: Color(0x26749A9A), spreadRadius: 3)
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

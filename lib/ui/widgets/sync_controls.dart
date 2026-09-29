// lib/ui/widgets/sync_controls.dart — the chrome that reflects SyncController state:
//   • resume-chip (.resume-chip) — "back to the playing verse" when detached
//   • chapter-action band (.ch-action) — "تشغيل الباب" after a chapter header is selected
//   • session chip (.session-chip) — resume the last listened verse on launch
// Ported from index.html + style.css + app.js (detachchange / chapterAction / sessionChip).
import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../theme.dart';
import '../../utils/arabic.dart';
import 'svg_icons.dart';

/// Floating "back to playing verse" chip (.resume-chip) — fixed, bottom-center.
class ResumeChip extends StatelessWidget {
  final AppController app;
  const ResumeChip({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final show = app.detached;
        return AnimatedSlide(
          offset: show ? Offset.zero : const Offset(0, 0.4),
          duration: const Duration(milliseconds: 250),
          curve: const Cubic(.22, .61, .36, 1),
          child: AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: IgnorePointer(
              ignoring: !show,
              child: GestureDetector(
                onTap: app.reattach,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [C.goldBright, C.gold],
                    ),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0xB3000000),
                          blurRadius: 28,
                          offset: Offset(0, 12),
                          spreadRadius: -10),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SvgIconWidget(SvgIcon.play, size: 18, color: C.onGold),
                      const SizedBox(width: 8),
                      Text.rich(
                        TextSpan(
                          style: naskh(size: 16, color: C.onGold),
                          children: [
                            const TextSpan(text: 'عودة إلى '),
                            TextSpan(
                                text: 'البيت ${ar(app.resumeVerse)}',
                                style: naskh(
                                    size: 16,
                                    weight: FontWeight.w700,
                                    color: C.onGold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Chapter-action band (.ch-action) — appears when a chapter header is selected.
class ChapterActionBand extends StatelessWidget {
  final AppController app;
  const ChapterActionBand({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final info = app.chapterActionInfo();
        if (info == null) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: C.goldFaint,
            border: Border.all(color: C.goldDeep),
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(info.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: naskh(size: 17.92, color: C.parch)),
                    const SizedBox(height: 2),
                    Text(info.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ui(size: 11.52, color: C.muted, tabular: true)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Opacity(
                opacity: info.canPlay ? 1 : 0.5,
                child: GestureDetector(
                  onTap: info.canPlay ? app.playSelectedChapter : null,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: C.gold,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SvgIconWidget(SvgIcon.play,
                            size: 15, color: C.colorDark),
                        const SizedBox(width: 6),
                        Text('تشغيل الباب',
                            style: ui(
                                size: 13.12,
                                weight: FontWeight.w700,
                                color: C.colorDark)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Resume-from-last-position chip (.session-chip) — shown once at launch.
class SessionChip extends StatelessWidget {
  final AppController app;
  const SessionChip({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final s = app.savedSession;
        if (s == null) return const SizedBox.shrink();
        return AnimatedSlide(
          offset: app.sessionChipVisible ? Offset.zero : const Offset(0, -0.18),
          duration: const Duration(milliseconds: 300),
          curve: const Cubic(.22, .61, .36, 1),
          child: AnimatedOpacity(
            opacity: app.sessionChipVisible ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: app.sessionChipVisible
                ? GestureDetector(
                    onTap: app.resumeFromChip,
                    child: Container(
                      height: 72,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0x1FC8860A),
                        border: Border.all(color: const Color(0x4DC8860A)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [C.goldBright, C.gold],
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const SvgIconWidget(SvgIcon.play,
                                size: 18, color: C.onGold),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('استكمال التلاوة',
                                    style: kufi(
                                        size: 12.48,
                                        weight: 600,
                                        color: C.goldBright)),
                                const SizedBox(height: 1),
                                Text.rich(
                                  TextSpan(children: [
                                    TextSpan(
                                        text: 'البيت ${ar(s.verseId)}',
                                        style: naskh(
                                            size: 14.72,
                                            weight: FontWeight.w600,
                                            color: C.gold)),
                                    TextSpan(
                                        text: ' · ${s.chapterName}',
                                        style: naskh(
                                            size: 14.72, color: C.parchDim)),
                                  ]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (s.verseFirst8.isNotEmpty)
                                  Text(s.verseFirst8,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: naskh(size: 14.4, color: C.muted)),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: app.dismissSessionChip,
                            child: Container(
                              width: 30,
                              height: 30,
                              alignment: Alignment.center,
                              child: Text('×',
                                  style: TextStyle(
                                      color: C.muted, fontSize: 21.6, height: 1)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

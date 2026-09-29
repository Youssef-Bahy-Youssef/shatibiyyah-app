// lib/ui/reader/reader_screen.dart — the v3 reader: the page, the top bar and the player.
//
// features-v3: fixed-page-layout, immersive-mode, page-header-info, mini-bar,
// now-playing-medallion, detach-resume-chip. The page sits in a rectangle computed
// once (ReaderLayout); the bar and the player fade over their reserved zones
// (show 180 ms cubic(.2,0,0,1) with −6 / +8 px of travel, hide 150 ms
// cubic(.4,0,1,1), reduced motion: opacity only in 100 ms), so nothing ever moves
// or covers the page.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme.dart' show kufi, naskh;
import '../../utils/arabic.dart';
import '../design/taysir_colors.dart';
import '../widgets/page_viewer.dart';
import '../widgets/verse_menu.dart';
import 'fixed_page_layout.dart';
import 'reader_controller.dart';
import 'shamsa.dart';
import 'tools_sheet.dart';

const _showCurve = Cubic(.2, 0, 0, 1);
const _hideCurve = Cubic(.4, 0, 1, 1);

class ReaderScreen extends StatelessWidget {
  final ReaderController reader;
  final VoidCallback? onMenu;
  final VoidCallback? onSearch;
  final VoidCallback? onTools;

  const ReaderScreen({super.key, required this.reader, this.onMenu, this.onSearch, this.onTools});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final mq = MediaQuery.of(context);
    final layout = ReaderLayout.compute(mq.size, mq.padding);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: t.bg,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.4),
              radius: 1.2,
              colors: [t.panel, t.bg],
              stops: const [0, 0.7],
            ),
          ),
          child: AnimatedBuilder(
            animation: reader,
            // Every child is positioned, so without `expand` the stack is 0×0 and clips them all.
            builder: (context, _) => Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fromRect(
                  rect: layout.page,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: PageViewer(controller: reader.viewer),
                  ),
                ),
                if (!reader.chromeVisible)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: mq.padding.bottom + 12,
                    child: IgnorePointer(
                      child: Center(
                        child: Text(ar(reader.page),
                            style: naskh(size: 13, color: t.muted.withValues(alpha: 0.7))),
                      ),
                    ),
                  ),
                _Chrome(
                  rect: layout.bar,
                  visible: reader.chromeVisible,
                  travel: -6,
                  child: _TopBar(
                    reader: reader,
                    onMenu: onMenu,
                    onSearch: onSearch,
                    onTools: onTools ?? () => showToolsSheet(context, reader),
                  ),
                ),
                _Chrome(
                  rect: layout.player,
                  visible: reader.chromeVisible,
                  travel: 8,
                  child: _PlayerBar(
                    reader: reader,
                    onOpen: () => showToolsSheet(context, reader, tab: ToolsTab.audio),
                  ),
                ),
                if (reader.detached && reader.playing)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: layout.player.top - 24,
                    child: Center(child: _ResumeChip(reader: reader)),
                  ),
                VerseMenu(
                  listenable: reader,
                  content: reader.content,
                  verse: () => reader.menuVerse,
                  anchor: (v) => reader.viewer.viewRectOfVerse(v)?.shift(layout.page.topLeft),
                  onClose: reader.closeMenu,
                  canPlay: () => reader.audioAvailable,
                  onPlayFrom: reader.tapVerse,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A chrome element over its reserved zone: fades and slides a few pixels, never moves the page.
class _Chrome extends StatelessWidget {
  final Rect rect;
  final bool visible;
  final double travel;
  final Widget child;
  const _Chrome({required this.rect, required this.visible, required this.travel, required this.child});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final duration = Duration(milliseconds: reduce ? 100 : (visible ? 180 : 150));
    final curve = visible ? _showCurve : _hideCurve;
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: duration,
          curve: curve,
          child: AnimatedSlide(
            offset: Offset(0, visible || reduce ? 0 : travel / rect.height),
            duration: duration,
            curve: curve,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final ReaderController reader;
  final VoidCallback? onMenu, onSearch, onTools;
  const _TopBar({required this.reader, this.onMenu, this.onSearch, this.onTools});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final chapter = reader.headerChapter;
    final part = reader.content.matn.partOf(chapter);
    final pages = reader.content.layout.pageCount;
    Widget icon(IconData i, String label, VoidCallback? onTap) => IconButton(
          tooltip: label,
          onPressed: onTap,
          icon: Icon(i, size: 21, color: t.text),
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.line),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Row(
        children: [
          icon(LucideIcons.menu, 'القائمة', onMenu),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 24,
                  child: Text(chapter.shortLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: naskh(size: 15.5, weight: FontWeight.w700, color: t.text, height: 1.5)),
                ),
                SizedBox(
                  height: 15,
                  child: Text('${part.title} · ص ${ar(reader.page)} من ${ar(pages)}',
                      maxLines: 1, style: kufi(size: 11.5, weight: 400, color: t.muted, height: 1.3)),
                ),
              ],
            ),
          ),
          icon(LucideIcons.search, 'بحث وانتقال', onSearch),
          icon(LucideIcons.slidersHorizontal, 'أدوات العرض والصوت', onTools),
        ],
      ),
    );
  }
}

class _PlayerBar extends StatelessWidget {
  final ReaderController reader;
  final VoidCallback? onOpen;
  const _PlayerBar({required this.reader, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final chapter = reader.chapter;
    final audio = reader.audioAvailable;
    final repeats = reader.settings.verseRepeats;
    final sections = reader.settings.sectionRepeats;
    final String line1, line2;
    if (!audio) {
      line1 = 'التلاوة غير منزّلة بعد';
      line2 = 'المتن والشروح تعمل دون تنزيل';
    } else if (reader.playing) {
      line1 = reader.inTitle ? chapter.shortLabel : 'البيت ${ar(reader.verse)} من ${ar(chapter.toVerse)}';
      line2 = reader.recording.reciterName;
    } else {
      line1 = 'متوقّف · البيت ${ar(reader.verse)}';
      line2 = reader.recording.reciterName;
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.line),
        boxShadow: const [BoxShadow(color: Color(0x52000000), blurRadius: 30, offset: Offset(0, 10))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 12, 4),
            child: Row(
              children: [
                if (audio)
                  Shamsa(
                    size: 50,
                    verse: reader.verse,
                    playing: reader.playing,
                    chip: (repeats == null || repeats > 1) && reader.playing
                        ? 'البيت ${ar(reader.verseRepetition)}/${repeats == null ? '∞' : ar(repeats)}'
                        : null,
                    ring: (sections == null || sections > 1) ? reader.sectionRepetition / (sections ?? 1) : null,
                  )
                else
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: t.gold, width: 1.5)),
                    child: Icon(LucideIcons.download, size: 22, color: t.goldText),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onOpen,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(line1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: kufi(size: 14, weight: 600, color: t.text)),
                        Text(line2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: kufi(size: 12, weight: 400, color: t.muted)),
                      ],
                    ),
                  ),
                ),
                if (audio) _Transport(reader: reader),
              ],
            ),
          ),
          if (audio) _ScopeProgress(reader: reader),
        ],
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  final ReaderController reader;
  const _Transport({required this.reader});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    Widget step(IconData icon, String label, VoidCallback onTap) => IconButton(
          tooltip: label,
          onPressed: onTap,
          icon: Icon(icon, size: 20, color: t.goldText),
          constraints: const BoxConstraints.tightFor(width: 44, height: 48),
        );
    return Directionality(
      textDirection: TextDirection.ltr, // transport and scrubber stay left-to-right
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        step(LucideIcons.skipBack, 'البيت السابق', reader.previous),
        Semantics(
          button: true,
          label: reader.playing ? 'إيقاف مؤقت' : 'تشغيل',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: reader.playPause,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [t.goldBright, t.gold]),
                boxShadow: [BoxShadow(color: t.gold.withValues(alpha: 0.5), blurRadius: 18, offset: const Offset(0, 6))],
              ),
              child: Icon(reader.playing ? LucideIcons.pause : LucideIcons.play, size: 22, color: t.onGold),
            ),
          ),
        ),
        step(LucideIcons.skipForward, 'البيت التالي', reader.next),
      ]),
    );
  }
}

/// Where playback is inside the current chapter (verse-based; exact scrubbing arrives with the tools sheet).
class _ScopeProgress extends StatelessWidget {
  final ReaderController reader;
  const _ScopeProgress({required this.reader});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final c = reader.chapter;
    final fraction = ((reader.verse - c.fromVerse + 0.4) / c.verseCount).clamp(0.0, 1.0);
    return Semantics(
      label: 'موضع التلاوة في الباب',
      value: '${ar(reader.verse - c.fromVerse + 1)} من ${ar(c.verseCount)}',
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(value: fraction, minHeight: 4, color: t.gold, backgroundColor: t.line),
          ),
        ),
      ),
    );
  }
}

class _ResumeChip extends StatelessWidget {
  final ReaderController reader;
  const _ResumeChip({required this.reader});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return GestureDetector(
      onTap: reader.resumeFollowing,
      child: Container(
        height: 48,
        padding: const EdgeInsetsDirectional.only(start: 8, end: 18),
        decoration: BoxDecoration(
          color: t.gold,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 10))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Shamsa(size: 32, verse: reader.verse, playing: true),
          const SizedBox(width: 8),
          Text('عودة إلى البيت ${ar(reader.verse)}', style: kufi(size: 15, weight: 600, color: t.onGold)),
        ]),
      ),
    );
  }
}

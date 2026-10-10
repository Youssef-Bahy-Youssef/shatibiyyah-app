// lib/ui/widgets/verse_menu.dart — the verse popover (item 3.5, ADRs 0009, 0011,
// 0019; index.html verse, v2.css .pop, .tiles, .more, .hl.spot).
//
// A long press on a verse spotlights it: a ring (lapis on paper, the night ink
// at night) with the scrim everywhere else. The popover grows from its arrow
// below the verse, else above it: the verse number in a khatam, where it is
// (chapter and page), its bookmark tag in carmine when it has one, both
// hemistichs, four 64 px tiles with «الشرح» the only filled one, then «نسخ»,
// «مشاركة», «تحديد أبيات» as text buttons drawn 44 px high in 48 px targets. A
// tap outside or Back closes it. Measured in handoff specs/verse-*.json.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/app_content.dart';
import '../../utils/arabic.dart';
import '../commentary/commentary_screen.dart';
import '../design/components/anchored_popover.dart';
import '../design/components/khatam.dart';
import '../design/components/tz_motion.dart';
import '../design/tokens.g.dart';
import '../design/tz_icon.dart';
import '../design/tz_theme.dart';
import '../reader/fixed_page_layout.dart';

/// The copy format of features-v3 (share-and-copy): number, chapter, both halves, attribution.
String verseCopyText(AppContent content, int verse) {
  final v = content.matn.verse(verse);
  final chapter = content.matn.chapterOfVerse(verse).shortLabel;
  return 'البيت ${ar(verse)} — $chapter\n${v.firstHemistich}\n${v.secondHemistich}\n— تيسير الشاطبية';
}

/// The same for a run of verses: the range and its first verse's chapter, then each
/// verse numbered, then the attribution.
String rangeCopyText(AppContent content, int from, int to) {
  if (from == to) return verseCopyText(content, from);
  final chapter = content.matn.chapterOfVerse(from).shortLabel;
  final lines = ['الأبيات ${ar(from)}–${ar(to)} — $chapter'];
  for (var n = from; n <= to; n++) {
    final v = content.matn.verse(n);
    lines
      ..add('${ar(n)}. ${v.firstHemistich}')
      ..add(v.secondHemistich);
  }
  lines.add('— تيسير الشاطبية');
  return lines.join('\n');
}

/// Hosted by a reader screen: [listenable] notifies when [verse] (the menu's verse,
/// null = closed) changes; [anchor] is where that verse is drawn on screen.
class VerseMenu extends StatelessWidget {
  final Listenable listenable;
  final AppContent content;
  final int? Function() verse;
  final Rect? Function(int verse) anchor;
  final VoidCallback onClose;

  /// «استمع»: enabled only when [canPlay] says a recording is on the device.
  final bool Function() canPlay;
  final void Function(int verse) onPlayFrom;

  /// «تحديد أبيات»: start selecting a run of verses here (hidden when null).
  final void Function(int verse)? onStartRange;

  /// «مشاركة»: open the share sheet for this verse (hidden when null).
  final void Function(int verse)? onShare;

  /// «المرجع» and «ملاحظة» (disabled when null); [bookmarked] / [hasNote] mark them
  /// as set, and [bookmarkTag] names the bookmark's tag in the header.
  final void Function(int verse)? onBookmark;
  final void Function(int verse)? onNote;
  final bool Function(int verse)? bookmarked;
  final bool Function(int verse)? hasNote;
  final String? Function(int verse)? bookmarkTag;

  /// «الشرح»: by default the commentary screen; the tablet's reader opens its split panel.
  final void Function(int verse)? onExplain;

  const VerseMenu({
    super.key,
    required this.listenable,
    required this.content,
    required this.verse,
    required this.anchor,
    required this.onClose,
    required this.canPlay,
    required this.onPlayFrom,
    this.onStartRange,
    this.onShare,
    this.onBookmark,
    this.onNote,
    this.bookmarked,
    this.hasNote,
    this.bookmarkTag,
    this.onExplain,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        final verse = this.verse();
        if (verse == null) return const SizedBox.shrink();
        final tz = TzTheme.of(context);
        final c = tz.colors;
        final size = MediaQuery.sizeOf(context);
        final safeBottom = MediaQuery.paddingOf(context).bottom;
        final avoid = ReaderTokens.dockInset(safeBottom);
        final rect = anchor(verse);
        return Stack(
          children: [
            Positioned.fill(
              child: Semantics(
                label: 'إغلاق القائمة',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: SpotlightScrim(
                    spot: rect,
                    ring: tz.night ? tz.nightInk.accent : c.lapis,
                    tint: tz.night ? tz.nightInk.accent.withValues(alpha: 0.16) : null,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: AnchoredPopover(
                key: ValueKey('verse-popover-$verse'),
                // A verse not drawn on this page (text mode has no row for it): from the bottom.
                anchor: rect ?? Rect.fromCenter(center: Offset(size.width / 2, size.height - avoid - 24), width: 0, height: 0),
                avoidBottom: avoid,
                // 6, not 8, at the bottom: the last row is a 48 dp target around 44 dp of drawing.
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                child: _body(context, c, verse),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _body(BuildContext context, TzColors c, int verse) {
    final v = content.matn.verse(verse);
    final chapter = content.matn.chapterOfVerse(verse);
    final page = content.layout.pageOfVerse(verse);
    final marked = bookmarked?.call(verse) ?? false;
    final tag = marked ? bookmarkTag?.call(verse) : null;
    void explain() {
      onClose();
      if (onExplain case final open?) {
        open(verse);
      } else {
        CommentaryScreen.open(context, content, verse);
      }
    }

    void copy() {
      Clipboard.setData(ClipboardData(text: verseCopyText(content, verse)));
      onClose();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('تم نسخ البيت مع الإسناد', style: TzType.label.copyWith(color: c.onSnack)), duration: const Duration(seconds: 2)),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Khatam(ar(verse), size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('البيت ${ar(verse)}', style: TzType.head.copyWith(color: c.ink)),
                  Text('${plainName(chapter.shortLabel)} · ص ${ar(page)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TzType.caption.copyWith(color: c.ink3)),
                ],
              ),
            ),
            if (tag case final word?) ...[
              const SizedBox(width: 8),
              TzIcon('bookmark', filled: true, size: 22, color: c.carmine),
              const SizedBox(width: 4),
              Text(word, style: TzType.caption.copyWith(color: c.carmine)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(v.firstHemistich, style: TzType.verse.copyWith(color: c.ink)),
        Text(v.secondHemistich, style: TzType.verse.copyWith(color: c.ink)),
        const SizedBox(height: 12),
        Row(
          children: [
            _Tile(label: 'الشرح', icon: 'book', primary: true, onTap: explain),
            const SizedBox(width: 6),
            _Tile(label: 'استمع', icon: 'listen', onTap: canPlay() ? () { onClose(); onPlayFrom(verse); } : null),
            const SizedBox(width: 6),
            _Tile(label: 'المرجع', icon: 'bookmark', marked: marked, onTap: onBookmark == null ? null : () { onClose(); onBookmark!(verse); }),
            const SizedBox(width: 6),
            _Tile(label: 'ملاحظة', icon: 'pen', marked: false, onTap: onNote == null ? null : () { onClose(); onNote!(verse); }),
          ],
        ),
        const SizedBox(height: 4),
        // Each button flexes, so the row fits a narrow body or large system text.
        Row(
          children: [
            Flexible(child: _More(label: 'نسخ', icon: 'copy', onTap: copy)),
            if (onShare != null) ...[const SizedBox(width: 2), Flexible(child: _More(label: 'مشاركة', icon: 'share', onTap: () { onClose(); onShare!(verse); }))],
            if (onStartRange != null) ...[const SizedBox(width: 2), Flexible(child: _More(label: 'تحديد أبيات', icon: 'select', onTap: () => onStartRange!(verse)))],
          ],
        ),
      ],
    );
  }
}

/// A 64 px tile (v2.css .tiles button): tonal, or the one filled «الشرح»; a marked
/// bookmark's glyph is carmine and filled. Disabled tiles are dimmed to 45 %.
class _Tile extends StatelessWidget {
  final String label, icon;
  final bool primary, marked;
  final VoidCallback? onTap;
  const _Tile({required this.label, required this.icon, this.primary = false, this.marked = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final ink = primary ? c.onAction : (marked ? c.carmine : c.ink2);
    return Expanded(
      child: MergeSemantics(
        child: Semantics(
          button: true,
          enabled: onTap != null,
          child: Opacity(
            opacity: onTap == null ? 0.45 : 1,
            child: Material(
              type: MaterialType.transparency,
              child: Ink(
                decoration: BoxDecoration(color: primary ? c.action : c.tonal, borderRadius: BorderRadius.circular(TzRadius.control)),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(TzRadius.control),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 64),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TzIcon(icon, filled: marked, size: 22, color: ink),
                        const SizedBox(height: 4),
                        Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            // The caption role on the spec's 20 dp line, which centres the pair in the tile.
                            style: TzType.caption
                                .copyWith(height: 20 / 12, fontWeight: FontWeight.w600, color: primary ? c.onAction : c.ink)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A text button (v2.css .more button, 44 px there; here the 48 px target).
class _More extends StatelessWidget {
  final String label, icon;
  final VoidCallback onTap;
  const _More({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: TzSize.touchTarget,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              TzIcon(icon, size: 18, color: c.ink2),
              const SizedBox(width: 6),
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TzType.label.copyWith(color: c.ink2))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The spotlight (v2.css .hl.spot): the scrim everywhere but [spot], a 2 px ring
/// of [ring] around it and an optional [tint] inside; fades in over 200 ms.
class SpotlightScrim extends StatelessWidget {
  final Rect? spot;
  final Color ring;
  final Color? tint;
  const SpotlightScrim({super.key, required this.spot, required this.ring, this.tint});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: tzDuration(context, TzMotion.medium),
      curve: TzMotion.standard,
      builder: (_, t, _) => Opacity(
        opacity: t,
        child: CustomPaint(painter: _SpotlightPainter(scrim: c.scrim, spot: spot, ring: ring, tint: tint), size: Size.infinite),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Color scrim, ring;
  final Color? tint;
  final Rect? spot;
  const _SpotlightPainter({required this.scrim, required this.spot, required this.ring, this.tint});

  @override
  void paint(Canvas canvas, Size size) {
    final all = Path()..addRect(Offset.zero & size);
    final hole = spot == null ? null : RRect.fromRectAndRadius(spot!, const Radius.circular(3));
    if (hole == null) {
      canvas.drawPath(all, Paint()..color = scrim);
      return;
    }
    canvas.drawPath(Path.combine(PathOperation.difference, all, Path()..addRRect(hole)), Paint()..color = scrim);
    if (tint case final color?) canvas.drawRRect(hole, Paint()..color = color);
    canvas.drawRRect(hole.inflate(1), Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = ring);
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.spot != spot || old.ring != ring || old.tint != tint || old.scrim != scrim;
}

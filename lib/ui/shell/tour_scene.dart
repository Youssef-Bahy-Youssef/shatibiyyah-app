// lib/ui/shell/tour_scene.dart — the picture on a tour card (tour_screen.dart).
//
// The real page 19 as the reader shows it (the night page at night), with what
// the card is about lying on it, each a small copy of the reader's own state:
//   card 1  the recited verse in its gilt wash, the dock under the page
//   card 2  a held verse in its ring with the scrim around it, and its menu
//   card 3  the commentary sheet: the books as tabs, the first one's opening words
// The verses' places come from the layout, the books and the reciter from the
// content. It is drawn at the size the page has in the reader on the design's
// phone (374 × 574, handoff specs/reader-*.json), with the type and the radii
// the real parts have, and the whole is scaled to the room it is given: so the
// marks keep their places on the page and nothing here has a size of its own.
// A picture, silent to a screen reader.
import 'package:flutter/material.dart';

import '../../data/app_content.dart';
import '../../data/commentary_repository.dart';
import '../../utils/arabic.dart';
import '../design/components/khatam.dart';
import '../design/components/ornament.dart';
import '../design/components/tz_motion.dart';
import '../design/night_page.dart';
import '../design/tokens.g.dart';
import '../design/tz_icon.dart';
import '../design/tz_theme.dart';
import '../widgets/verse_menu.dart' show SpotlightScrim;

class TourScene extends StatelessWidget {
  final AppContent content;

  /// Which card: 0, 1 or 2.
  final int card;

  /// What card 3's sheet says ([loadOpening], read once by whoever shows the scene).
  final Future<String> opening;
  const TourScene({super.key, required this.content, required this.card, required this.opening});

  /// The verses shown on page 19: the one recited, and the one held.
  static const int recited = 226, held = 229;

  /// For tests: the page, the recited verse's wash on it, the held verse's
  /// menu and the commentary sheet.
  static const pageKey = ValueKey('tour-page');
  static const recitedKey = ValueKey('tour-recited');
  static const menuKey = ValueKey('tour-menu');
  static const sheetKey = ValueKey('tour-sheet');

  /// The page as wide as the reader draws it on a 390 px phone, and as tall as a scan is.
  static const double _w = 374, _h = _w * 1735 / 1130;

  /// The opening of the first book's explanation of the recited verse.
  static Future<String> loadOpening(AppContent content) async {
    final books = content.books;
    final blocks = await books.blocksForVerse(books.books.first.id, recited);
    if (blocks.isEmpty) return '';
    final segments = await books.segments(blocks.first.id);
    final text = segments.map((s) => s.text.trim()).join(' ').replaceAll(RegExp(r'\s+'), ' ');
    return text.length > 420 ? text.substring(0, 420) : text;
  }

  @override
  Widget build(BuildContext context) {
    final tz = TzTheme.of(context);
    final c = tz.colors;
    // The page's own marks follow the page: the night tokens on the night page.
    final onPage = tz.night ? TzColors.night : TzColors.paper;
    const k = _w / 1130;
    Rect box(int verse) {
      final r = content.layout.verseRegion(verse).rect;
      return Rect.fromLTRB(r.left * k, r.top * k, r.right * k, r.bottom * k);
    }

    final recited = box(TourScene.recited), held = box(TourScene.held);
    Widget image = Image.asset(
      'assets/pages/page019.webp',
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
    );
    if (tz.night) {
      image = ColorFiltered(colorFilter: ColorFilter.matrix(nightInkMatrix(tz.nightInk)), child: image);
    }
    final radius = BorderRadius.circular(TzRadius.control);
    return ExcludeSemantics(
      child: MediaQuery.withNoTextScaling(
        child: FittedBox(
          child: SizedBox(
            key: TourScene.pageKey,
            width: _w,
            height: _h,
            child: DecoratedBox(
              decoration: BoxDecoration(borderRadius: radius, boxShadow: c.float),
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: c.lineSoft)),
                child: ClipRRect(
                  borderRadius: radius,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      image,
                      // Cards 1 and 3: the recited verse as the reader's page marks it (v2.css
                      // .hl.play): the gilt wash on its box with 3 px corners, and a 3 px gilt
                      // mark in the margin at its start, 3 px out and inset 4 px.
                      Positioned.fromRect(
                        rect: recited,
                        child: _Shown(
                          card != 1,
                          child: DecoratedBox(
                            key: TourScene.recitedKey,
                            decoration: BoxDecoration(color: onPage.giltWash, borderRadius: BorderRadius.circular(3)),
                          ),
                        ),
                      ),
                      Positioned(
                        left: recited.right + 3,
                        top: recited.top + 4,
                        width: 3,
                        height: recited.height - 8,
                        child: _Shown(
                          card != 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: onPage.gilt, borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                      ),
                      // Cards 1 and 2: the dock (card 3's sheet covers it).
                      Positioned(
                        left: TzSpace.s16,
                        right: TzSpace.s16,
                        bottom: TzSpace.s16,
                        child: _MiniDock(reciter: content.recordings.defaultRecording.reciterName, playing: card == 0),
                      ),
                      // Card 2: the held verse in its ring, the rest under the scrim, and its menu.
                      _Shown(
                        card == 1,
                        child: SpotlightScrim(spot: held, ring: tz.night ? tz.nightInk.accent : c.lapis),
                      ),
                      Positioned(
                        left: 36,
                        right: 36,
                        top: held.bottom + TzSpace.s12,
                        child: _Shown(card == 1, rise: true, child: const _MiniMenu(key: TourScene.menuKey)),
                      ),
                      // Card 3: the commentary sheet, with the books as its tabs.
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: _h * 0.6,
                        child: AnimatedSlide(
                          offset: card == 2 ? Offset.zero : const Offset(0, 1.05),
                          duration: tzDuration(context, TzMotion.long),
                          curve: TzMotion.emphasized,
                          child: _MiniSheet(key: TourScene.sheetKey, books: content.books.books, opening: opening),
                        ),
                      ),
                    ],
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

/// Fades its child in and out with the card; [rise] also lifts it into place.
class _Shown extends StatelessWidget {
  final bool shown, rise;
  final Widget child;
  const _Shown(this.shown, {this.rise = false, required this.child});

  @override
  Widget build(BuildContext context) {
    final duration = tzDuration(context, TzMotion.medium);
    Widget w = AnimatedOpacity(opacity: shown ? 1 : 0, duration: duration, curve: TzMotion.standard, child: child);
    if (rise) {
      w = AnimatedSlide(
        offset: shown ? Offset.zero : const Offset(0, 0.06),
        duration: duration,
        curve: TzMotion.standard,
        child: w,
      );
    }
    return IgnorePointer(child: w);
  }
}

/// The dock's playing row in small (62 px, the binding): the verse in its
/// khatam, the reciter, and play or pause on the ivory disc.
class _MiniDock extends StatelessWidget {
  final String reciter;
  final bool playing;
  const _MiniDock({required this.reciter, required this.playing});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return Container(
      height: 62,
      padding: const EdgeInsetsDirectional.fromSTEB(10, 0, TzSpace.s12, 0),
      decoration: BoxDecoration(color: c.cover, borderRadius: BorderRadius.circular(TzRadius.dock), boxShadow: c.dock),
      child: Row(
        children: [
          Khatam(ar(TourScene.recited), size: 44, onCover: true),
          const SizedBox(width: TzSpace.s8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('البيت ${ar(TourScene.recited)}',
                    maxLines: 1, style: TzType.label.copyWith(fontWeight: FontWeight.w700, color: c.onCover)),
                Text(reciter,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TzType.caption.copyWith(fontWeight: FontWeight.w400, color: c.coverMute)),
              ],
            ),
          ),
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.onCover, shape: BoxShape.circle),
            child: TzIcon(playing ? 'pause' : 'play', filled: true, size: 18, color: c.cover),
          ),
        ],
      ),
    );
  }
}

/// The verse menu in small: the held verse's number, and the four 64 px tiles
/// with «الشرح» the filled one. (The real one also has the verse's words and a
/// row of «نسخ», «مشاركة», «تحديد أبيات».)
class _MiniMenu extends StatelessWidget {
  const _MiniMenu({super.key});

  static const _tiles = [('book', 'الشرح'), ('listen', 'استمع'), ('bookmark', 'المرجع'), ('pen', 'ملاحظة')];

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        // The arrow that ties the menu to its verse.
        Positioned(top: -6, child: Lozenge(size: 14, radius: 2, color: c.raised)),
        Container(
          padding: const EdgeInsets.fromLTRB(TzSpace.s12, 10, TzSpace.s12, TzSpace.s12),
          decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(TzRadius.card), boxShadow: c.float),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Khatam(ar(TourScene.held), size: 40),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('البيت ${ar(TourScene.held)}', maxLines: 1, style: TzType.head.copyWith(color: c.ink)),
                  ),
                ],
              ),
              const SizedBox(height: TzSpace.s8),
              Row(
                children: [
                  for (final (i, (icon, label)) in _tiles.indexed) ...[
                    if (i > 0) const SizedBox(width: TzSpace.s8),
                    Expanded(
                      child: Container(
                        height: 64,
                        decoration: BoxDecoration(
                          color: i == 0 ? c.action : c.tonal,
                          borderRadius: BorderRadius.circular(TzRadius.control),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TzIcon(icon, size: 22, color: i == 0 ? c.onAction : c.ink),
                            const SizedBox(height: TzSpace.s4),
                            Text(label,
                                maxLines: 1,
                                style: TzType.caption.copyWith(fontWeight: FontWeight.w600, color: i == 0 ? c.onAction : c.ink)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The commentary sheet in small: its grip, the books as tabs with the first
/// one open, its author, and the opening of what it says about the verse.
class _MiniSheet extends StatelessWidget {
  final List<Book> books;
  final Future<String> opening;
  const _MiniSheet({super.key, required this.books, required this.opening});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final open = books.first;
    final died = open.deathYearH;
    final byline = [?open.author, if (died != null) 'ت ${ar(died)}هـ'].join(' · ');
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(TzRadius.sheet)),
        border: Border(top: BorderSide(color: c.lineSoft)),
        boxShadow: c.float,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: TzSpace.s8),
              decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(TzRadius.pill)),
            ),
          ),
          // Longer names than these three shrink to fit; they never push past the sheet.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              children: [
                for (final book in books)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 18),
                    child: IntrinsicWidth(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            book.shortTitle,
                            maxLines: 1,
                            style: TzType.chapter.copyWith(
                              fontWeight: book == open ? FontWeight.w700 : FontWeight.w500,
                              color: book == open ? c.ink : c.ink3,
                            ),
                          ),
                          Container(height: 2, color: book == open ? c.lapis : null),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(height: 1, color: c.lineSoft),
          const SizedBox(height: TzSpace.s8),
          Text(byline, maxLines: 1, style: TzType.caption.copyWith(color: c.ink3)),
          const SizedBox(height: TzSpace.s4),
          // The words run on under the edge, as in a sheet not yet pulled up: they fade into it.
          Expanded(
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [c.surface.withValues(alpha: 0), c.surface.withValues(alpha: 0), c.surface],
                  stops: const [0, 0.6, 1],
                ),
              ),
              child: FutureBuilder<String>(
                future: opening,
                builder: (context, snapshot) => Text(
                  snapshot.data ?? '',
                  textAlign: TextAlign.justify,
                  overflow: TextOverflow.clip,
                  style: TzType.commentary.copyWith(color: c.ink),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

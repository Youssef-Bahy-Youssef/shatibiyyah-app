// lib/ui/shell/tour_screen.dart — first run: the tour, then «اختر القارئ»
// (features-v3 onboarding-tour, reciter-catalog).
//
// Three short cards over the real page (page 19, not an illustration), each
// showing the reader as it will look (tour_scene.dart): the verse being
// recited, with the dock under it; a verse held, with its menu; the commentary
// sheet with the three books. The page stays where it is and what lies on it
// changes. «تخطَّ» is always there, a swipe or Back moves between the cards, and
// «حول» can replay the tour. No permission is asked here. Card 3 is «الشروح
// الثلاثة على جهازك» (plan rev. 3: the prototype's third card hinted at the
// quiz, which v2 drops).
//
// Then the reciter: the pages and books already work; pick a voice, and either
// download it and start (the download goes on while reading) or «لاحقًا».
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/audio_library.dart';
import '../../data/app_content.dart';
import '../../services/preferences_service.dart';
import '../../utils/arabic.dart';
import '../design/components/ornament.dart';
import '../design/components/tz_button.dart';
import '../design/components/tz_motion.dart';
import '../design/taysir_logo.dart';
import '../design/tokens.g.dart';
import '../design/tz_theme.dart';
import 'downloads_screen.dart' show ReciterOption;
import 'tour_scene.dart';

/// Set once the first run is over (tour and pick seen or skipped).
const String kTourDonePref = 'v2.tour.done';

bool tourDone(Prefs prefs) => prefs.getString(kTourDonePref) == '1';

const _cards = [
  (
    title: 'المتن أولًا',
    text: 'صفحات الشاطبية كما كُتبت، والبيت الذي يُتلى مظلَّل.',
  ),
  (
    title: 'الشرح والمراجعة حول البيت',
    text: 'اضغط مطوّلًا على بيت لتقرأ شرحه، أو تسمعه من موضعه، أو تضع عليه مرجعًا أو ملاحظة تعود إليها.',
  ),
  (
    title: 'الشروح الثلاثة على جهازك',
    text: 'الوافي وإبراز المعاني وسراج القارئ مع الصفحات والنص، كلها على جهازك وتعمل دون اتصال. التلاوة وحدها تُنزَّل، مرة واحدة.',
  ),
];

class TourScreen extends StatefulWidget {
  final AppContent content;
  final AudioLibrary? library;
  final Prefs prefs;

  /// Replayed from «حول»: the reciter step is skipped.
  final bool replay;
  const TourScreen({super.key, required this.content, required this.library, required this.prefs, this.replay = false});

  static Future<void> open(BuildContext context, {required AppContent content, AudioLibrary? library, required Prefs prefs, bool replay = false}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => TourScreen(content: content, library: library, prefs: prefs, replay: replay),
      ));

  @override
  State<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends State<TourScreen> {
  int _card = 0;
  bool _picking = false;

  /// What card 3's sheet says: read once, however often the cards come and go.
  late final Future<String> _opening = TourScene.loadOpening(widget.content);

  void _finish() {
    widget.prefs.setString(kTourDonePref, '1');
    Navigator.of(context).pop();
  }

  void _next() {
    if (_card < _cards.length - 1) {
      setState(() => _card++);
    } else {
      _toPick();
    }
  }

  /// The card before this one; from the reciter, the card it was reached from.
  void _back() {
    if (_picking) {
      setState(() => _picking = false);
    } else if (_card > 0) {
      setState(() => _card--);
    }
  }

  void _toPick() {
    if (widget.replay || widget.library == null) {
      _finish();
    } else {
      setState(() => _picking = true);
    }
  }

  /// A swipe turns the card the way a page turns in Arabic (the tour is always
  /// right to left): a swipe to the right brings the next card. It moves between
  /// the cards only; ending the tour is the button's.
  void _swiped(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < 200) return;
    if (v < 0) {
      _back();
    } else if (_card < _cards.length - 1) {
      setState(() => _card++);
    }
  }

  static const double _textSide = 28, _titleGap = 6;

  /// The height of the tallest card's words (title, gap, text) in a column
  /// [width] wide: every card keeps that much room, so the page does not move
  /// from one card to the next, whatever wraps.
  double _tallestWords(BuildContext context, double width) {
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    double height(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: base.merge(style)),
        textDirection: TextDirection.rtl,
        textScaler: scaler,
      )..layout(maxWidth: math.max(0, width));
      final h = painter.height;
      painter.dispose();
      return h;
    }

    return [for (final card in _cards) height(card.title, TzType.title) + _titleGap + height(card.text, TzType.body)]
        .reduce(math.max);
  }

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return Directionality(
      textDirection: TextDirection.rtl,
      // Back goes a card back; on the first card it leaves, as before.
      child: PopScope(
        canPop: !_picking && _card == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: Scaffold(
          backgroundColor: c.bg,
          body: SafeArea(
            child: _picking ? _PickReciter(library: widget.library!, onDone: _finish) : _tour(context),
          ),
        ),
      ),
    );
  }

  Widget _tour(BuildContext context) {
    final tz = TzTheme.of(context);
    final c = tz.colors;
    final card = _cards[_card];
    final last = _card == _cards.length - 1;
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: _swiped,
        // A screen reader moves with the buttons; the swipe adds nothing to say.
        excludeFromSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 8, 0),
              child: Row(
                children: [
                  ExcludeSemantics(
                    // the name is beside it
                    child: TaysirLogo(size: 34, palette: tz.night ? LogoPalette.cover : LogoPalette.paper),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('تيسير الشاطبية',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TzType.chapter.copyWith(fontWeight: FontWeight.w700, color: c.ink)),
                  ),
                  TextButton(
                    onPressed: _toPick,
                    style: TextButton.styleFrom(
                      foregroundColor: c.ink2,
                      minimumSize: const Size(TzSize.touchTarget, TzSize.touchTarget),
                    ),
                    child: Text('تخطَّ', style: TzType.label.copyWith(color: c.ink2)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
                child: TourScene(content: widget.content, card: _card, opening: _opening),
              ),
            ),
            // Large text makes the words taller, never the screen: past half of it they scroll.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: box.maxHeight / 2),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: _textSide),
                child: AnimatedSwitcher(
                  duration: tzDuration(context, TzMotion.medium),
                  switchInCurve: TzMotion.standard,
                  switchOutCurve: TzMotion.exit,
                  layoutBuilder: (current, previous) =>
                      Stack(alignment: AlignmentDirectional.topStart, children: [...previous, ?current]),
                  child: ConstrainedBox(
                    key: ValueKey(_card),
                    constraints: BoxConstraints(minHeight: _tallestWords(context, box.maxWidth - 2 * _textSide)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(header: true, child: Text(card.title, style: TzType.title.copyWith(color: c.ink))),
                        const SizedBox(height: _titleGap),
                        Text(card.text, style: TzType.body.copyWith(color: c.ink2)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Row(
                children: [
                  _Steps(count: _cards.length, at: _card),
                  const Spacer(),
                  SizedBox(
                    width: 148,
                    child: TzButton.primary(
                      label: last && !widget.replay ? 'اختر القارئ' : (last ? 'تم' : 'التالي'),
                      onPressed: _next,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where the tour is: a lozenge per card, the current one gilt (as under the dock's tab).
class _Steps extends StatelessWidget {
  final int count, at;
  const _Steps({required this.count, required this.at});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return Semantics(
      container: true,
      label: '${ar(at + 1)} من ${ar(count)}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            SizedBox(
              width: 18,
              height: 18,
              child: Center(child: Lozenge(size: i == at ? 9 : 6, radius: 1, color: i == at ? c.gilt : c.line)),
            ),
        ],
      ),
    );
  }
}

/// «اختر القارئ»: the pages and books already work; choose a voice.
class _PickReciter extends StatelessWidget {
  final AudioLibrary library;
  final VoidCallback onDone;
  const _PickReciter({required this.library, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final r = library.chosen;
        final onDevice = library.isOnDevice(r);
        return ListView(
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 24),
          children: [
            // A screen of its own: the unwan, as on the dock's tabs.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Semantics(header: true, child: Text('اختر القارئ', style: TzType.display.copyWith(color: c.ink))),
            ),
            const Padding(padding: EdgeInsets.fromLTRB(20, 6, 20, 0), child: GiltRule()),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Text('تعمل الصفحات والشروح الآن دون تنزيل. اختر صوتًا تسمعه مع كل بيت.',
                  style: TzType.body.copyWith(color: c.ink2)),
            ),
            for (final rec in library.recordings)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                // The download is offered below, with its size: it does not start by itself here.
                child: ReciterOption(library: library, recording: rec, onPick: () => library.choose(rec, startDownload: false)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TzButton.primary(
                label: onDevice ? 'ابدأ التلاوة' : 'تنزيل ${megabytes(r.localBytes)} والبدء',
                icon: onDevice ? 'play' : 'down',
                iconFilled: onDevice,
                onPressed: () {
                  if (!onDevice) library.download(r); // goes on while reading
                  onDone();
                },
              ),
            ),
            if (!onDevice)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Center(
                  child: TextButton(
                    onPressed: onDone,
                    style: TextButton.styleFrom(
                      foregroundColor: c.ink2,
                      minimumSize: const Size(TzSize.touchTarget, TzSize.touchTarget),
                    ),
                    child: Text('لاحقًا، ابدأ بالقراءة', style: TzType.label.copyWith(color: c.ink2)),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// lib/ui/shell/tour_screen.dart — first run: the tour, then «اختر القارئ»
// (features-v3 onboarding-tour, reciter-catalog).
//
// Three short cards over the real page (page 19, not an illustration): the
// manuscript with the playing verse; a verse held for its menu; the three books on
// the device. «تخطَّ» is always there, and «حول» can replay the tour. No
// permission is asked here. Card 3 is «الشروح الثلاثة على جهازك» (plan rev. 3: the
// prototype's third card hinted at the quiz, which v2 drops).
//
// Then the reciter: the pages and books already work; pick a voice, and either
// download it and start (the download goes on while reading) or «لاحقًا».
import 'package:flutter/material.dart';

import '../../app/audio_library.dart';
import '../../data/app_content.dart';
import '../../services/preferences_service.dart';
import '../design/tokens.g.dart';
import '../../utils/arabic.dart';
import '../design/taysir_colors.dart';
import '../design/taysir_logo.dart';
import 'downloads_screen.dart' show ReciterOption;

/// Set once the first run is over (tour and pick seen or skipped).
const String kTourDonePref = 'v2.tour.done';

bool tourDone(Prefs prefs) => prefs.getString(kTourDonePref) == '1';

const _cards = [
  (
    title: 'المخطوط أولًا',
    text: 'صفحات الشاطبية كما كُتبت، والبيت الذي يُتلى مظلَّل. المس الصفحة لإخفاء كل شيء.',
    verse: 226,
    held: false,
  ),
  (
    title: 'الشرح والمراجعة حول البيت',
    text: 'اضغط مطوّلًا على بيت لتقرأ شرحه، أو تسمعه من موضعه، أو تضع عليه مرجعًا أو ملاحظة تعود إليها.',
    verse: 229,
    held: true,
  ),
  (
    title: 'الشروح الثلاثة على جهازك',
    text: 'الوافي وإبراز المعاني وسراج القارئ مع الصفحات والنص، كلها على جهازك وتعمل دون اتصال. التلاوة وحدها تُنزَّل، مرة واحدة.',
    verse: null,
    held: false,
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

  void _toPick() {
    if (widget.replay || widget.library == null) {
      _finish();
    } else {
      setState(() => _picking = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          child: _picking ? _PickReciter(library: widget.library!, onDone: _finish) : _tour(t),
        ),
      ),
    );
  }

  Widget _tour(TaysirColors t) {
    final card = _cards[_card];
    final last = _card == _cards.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(
            children: [
              const TaysirLogo(size: 34),
              const SizedBox(width: 10),
              Text('${ar(_card + 1)} من ${ar(_cards.length)}', style: TzType.label.copyWith(color: t.muted)),
              const Spacer(),
              TextButton(
                onPressed: _toPick,
                child: Text('تخطَّ', style: TzType.label.copyWith(color: t.goldText)),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _MiniPage(content: widget.content, verse: card.verse, held: card.held),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(card.title, style: TzType.title.copyWith(color: t.text)),
              const SizedBox(height: 10),
              SizedBox(
                height: 100,
                child: Text(card.text, style: TzType.commentary.copyWith(color: t.dim)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Row(
            children: [
              for (var i = 0; i < _cards.length; i++) ...[
                AnimatedContainer(
                  duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 200),
                  width: i == _card ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _card ? t.gold : t.line,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              const Spacer(),
              FilledButton(
                onPressed: _next,
                style: FilledButton.styleFrom(
                  backgroundColor: t.gold,
                  minimumSize: const Size(140, 52),
                  shape: const StadiumBorder(),
                ),
                child: Text(last && !widget.replay ? 'اختر القارئ' : (last ? 'تم' : 'التالي'),
                    style: TzType.head.copyWith(color: t.onGold)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The real page 19, small, with a verse highlighted as playing or as held.
class _MiniPage extends StatelessWidget {
  final AppContent content;
  final int? verse;
  final bool held;
  const _MiniPage({required this.content, required this.verse, required this.held});

  @override
  Widget build(BuildContext context) {
    const page = 19;
    return AspectRatio(
      aspectRatio: 1130 / 1735,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: TaysirColors.of(context).float,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset('assets/pages/page${page.toString().padLeft(3, '0')}.webp', fit: BoxFit.fill),
              if (verse != null)
                CustomPaint(painter: _VerseMark(content.layout.verseRegion(verse!).rect, held: held)),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerseMark extends CustomPainter {
  final Rect box; // in scan pixels (1130 × 1735)
  final bool held;
  const _VerseMark(this.box, {required this.held});

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 1130;
    final rect = Rect.fromLTRB(box.left * k - 4, box.top * k - 4, box.right * k + 4, box.bottom * k + 4);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    if (held) {
      // The rest of the page dims around the held verse, as under the verse menu.
      canvas.drawDRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.zero),
        rr,
        Paint()..color = TzColors.paper.scrim,
      );
    }
    canvas.drawRRect(rr, Paint()..color = held ? TzColors.paper.giltWashSoft : TzColors.paper.giltWash);
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = held ? 2.5 : 2
        ..color = TzColors.paper.gilt,
    );
  }

  @override
  bool shouldRepaint(_VerseMark old) => old.box != box || old.held != held;
}

/// «اختر القارئ»: the pages and books already work; choose a voice.
class _PickReciter extends StatelessWidget {
  final AudioLibrary library;
  final VoidCallback onDone;
  const _PickReciter({required this.library, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final r = library.current;
        final onDevice = library.isOnDevice(r);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            Text('اختر القارئ', style: TzType.title.copyWith(color: t.text)),
            const SizedBox(height: 6),
            Text('تعمل الصفحات والشروح الآن دون تنزيل. اختر صوتًا تسمعه مع كل بيت.',
                style: TzType.commentary.copyWith(color: t.dim)),
            const SizedBox(height: 16),
            for (final rec in library.recordings) ...[
              ReciterOption(library: library, recording: rec, onPick: () => library.choose(rec)),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (!onDevice) library.download(r); // goes on while reading
                onDone();
              },
              style: FilledButton.styleFrom(
                backgroundColor: t.gold,
                minimumSize: const Size.fromHeight(52),
                shape: const StadiumBorder(),
              ),
              child: Text(onDevice ? 'ابدأ التلاوة' : 'تنزيل ${megabytes(r.localBytes)} والبدء',
                  style: TzType.head.copyWith(color: t.onGold)),
            ),
            if (!onDevice) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onDone,
                child: Text('لاحقًا، ابدأ بالقراءة', style: TzType.label.copyWith(color: t.goldText)),
              ),
            ],
          ],
        );
      },
    );
  }
}

// lib/ui/reader/player_sheet.dart — the player (item 3.7, ADRs 0004, 0005, 0019;
// handoff player-main, player-repeat, player-speed).
//
// The verse is the hero: the one being recited with its khatam, the next one
// faded under a dashed line. Then where the recitation is in its section (a
// scrubber with a tick at each verse), transport, and four value tiles (speed,
// verse repeat with its «٢/٣» counter, section repeat, gap), each opening a
// picker of 56 px options under one sentence that states the rule. Last, the
// spoken chapter titles and the reciter.
//
// The sheet opens from the dock's now-playing row, 40 px under the status bar,
// and scrolls when the screen is short or the text large.
import 'package:flutter/material.dart';

import '../../data/settings_store.dart';
import '../../utils/arabic.dart';
import '../design/components/khatam.dart';
import '../design/components/play_disc.dart';
import '../design/components/section_scrubber.dart';
import '../design/components/stat_tile.dart';
import '../design/components/tz_picker.dart';
import '../design/components/tz_sheet.dart';
import '../design/components/tz_switch.dart';
import '../design/tokens.g.dart';
import '../design/tz_icon.dart';
import '../design/tz_theme.dart';
import '../shell/downloads_screen.dart';
import 'reader_controller.dart';

Future<void> showPlayerSheet(BuildContext context, ReaderController reader) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (_) => PlayerSheet(reader: reader),
    );

/// «∞» for a repeat without end.
String repeatLabel(int? n) => n == null ? '∞' : ar(n);
String speedLabel(double v) => '${ar(v)}×';
String gapLabel(int ms) => ms == 0 ? 'بدون' : '${ar(ms ~/ 1000)} ث';

/// The scrubber shows a tick per verse up to this many verses; beyond, they would merge.
const int kMaxScrubberTicks = 40;

class PlayerSheet extends StatelessWidget {
  final ReaderController reader;
  const PlayerSheet({super.key, required this.reader});

  static const heroKey = ValueKey('player-hero');
  static const upNextKey = ValueKey('player-up-next');
  static const bigPlayKey = ValueKey('player-big-play');

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return SizedBox(
      height: media.size.height - statusBarHeight(context) - 40,
      // A picker over the player dims the player, not the reader behind it again.
      child: PickerHost(
        radius: TzRadius.sheet,
        child: TzSheet(
        child: ListenableBuilder(
          listenable: Listenable.merge([reader, ?reader.library]),
          builder: (context, _) {
            // The recording left the device while the sheet was open: nothing to show.
            if (reader.engine == null) return const SizedBox.expand();
            return SingleChildScrollView(
              padding: EdgeInsets.only(bottom: media.viewPadding.bottom + 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context),
                  _hero(context),
                  _scrubber(context),
                  _transport(context),
                  const SizedBox(height: 8),
                  _tiles(context),
                  const SizedBox(height: 10),
                  _rows(context),
                ],
              ),
            );
          },
        ),
        ),
      ),
    );
  }

  // The section and the reciter over the chapter; «إغلاق المشغّل» at the end (44 px in a 48 px target).
  Widget _header(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final scope = reader.section!;
    return SizedBox(
      height: 52,
      child: Stack(
        children: [
          PositionedDirectional(
            start: 12,
            end: 68,
            top: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المقطع ${isolatedRange(scope.fromVerse, scope.toVerse)} · ${reader.recording.reciterName}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TzType.caption.copyWith(color: c.ink3)),
                Text(plainName(reader.chapter.shortLabel),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TzType.head.copyWith(color: c.ink)),
              ],
            ),
          ),
          PositionedDirectional(
            end: 14,
            top: 4,
            child: _Glyph(
                icon: 'collapse', label: 'إغلاق المشغّل', size: 22, color: c.ink2, onTap: () => Navigator.of(context).pop()),
          ),
        ],
      ),
    );
  }

  Widget _hero(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final verse = reader.content.matn.verse(reader.verse);
    final scope = reader.section!;
    final next = reader.verse < scope.toVerse ? reader.content.matn.verse(reader.verse + 1) : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
      child: Column(
        children: [
          Khatam(ar(reader.verse), size: 46),
          const SizedBox(height: 13),
          Semantics(
            label: 'البيت ${ar(reader.verse)}',
            child: Text('${verse.firstHemistich}\n${verse.secondHemistich}',
                key: heroKey, textAlign: TextAlign.center, style: TzType.hero.copyWith(color: c.ink)),
          ),
          if (next != null) ...[
            const SizedBox(height: 10),
            CustomPaint(
              painter: _DashedLine(c.line),
              child: Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('التالي · البيت ${ar(reader.verse + 1)}',
                        textAlign: TextAlign.center, style: TzType.caption.copyWith(color: c.ink3)),
                    Text(next.firstHemistich,
                        key: upNextKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TzType.chapter.copyWith(
                            color: c.ink3, fontWeight: FontWeight.w400, height: 30 / TzType.chapter.fontSize!)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // The section as time (SectionTime): what the dock's bar shows too.
  Widget _scrubber(BuildContext context) {
    final engine = reader.engine!;
    final scope = reader.section!, time = reader.sectionTime!;
    final count = scope.toVerse - scope.fromVerse + 1;
    final at = (reader.verse - scope.fromVerse + 1).clamp(1, count);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: StreamBuilder<int>(
        stream: engine.audio.positionMs,
        builder: (context, _) {
          final elapsed = reader.sectionElapsedMs(time);
          return SectionScrubber(
            progress: time.fraction(elapsed),
            ticks: [
              if (count <= kMaxScrubberTicks)
                for (var v = scope.fromVerse + 1; v <= scope.toVerse; v++) time.fraction(time.cueMs(v)),
            ],
            start: playTime(elapsed),
            middle: 'البيت ${ar(at)} من ${ar(count)}',
            end: playTime(time.totalMs),
            onSeek: (f) => reader.tapVerse(time.verseAt((f * time.totalMs).round())),
          );
        },
      ),
    );
  }

  Widget _transport(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return SizedBox(
      height: 72,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Glyph(icon: 'prev', label: 'البيت السابق', size: 26, color: c.ink, target: 52, filled: true, onTap: reader.previous),
          const SizedBox(width: 32),
          PlayDisc(key: bigPlayKey, playing: reader.playing, onTap: reader.playPause),
          const SizedBox(width: 32),
          _Glyph(icon: 'next', label: 'البيت التالي', size: 26, color: c.ink, target: 52, filled: true, onTap: reader.next),
        ],
      ),
    );
  }

  Widget _tiles(BuildContext context) {
    final s = reader.settings;
    String? counter(int? repeats, int at) => repeats == 1 ? null : '${ar(at)}/${repeatLabel(repeats)}';
    final tiles = [
      StatTile(value: speedLabel(reader.speed), label: 'السرعة', onTap: () => _pickSpeed(context)),
      StatTile(
        value: repeatLabel(s.verseRepeats),
        label: 'تكرار البيت',
        badge: counter(s.verseRepeats, reader.verseRepetition),
        onTap: () => _pickRepeat(context, verse: true),
      ),
      StatTile(
        value: repeatLabel(s.sectionRepeats),
        label: 'تكرار المقطع',
        badge: counter(s.sectionRepeats, reader.sectionRepetition),
        onTap: () => _pickRepeat(context, verse: false),
      ),
      StatTile(value: gapLabel(s.gapMs), label: 'الفاصل', onTap: () => _pickGap(context)),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, tile) in tiles.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: tile),
          ],
        ],
      ),
    );
  }

  Widget _rows(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final library = reader.library;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _Row(
            icon: 'mic',
            label: 'عناوين الأبواب',
            trailing: TzSwitch(
              semanticLabel: 'تلاوة عناوين الأبواب',
              value: reader.settings.playTitles,
              onWord: 'تُتلى',
              offWord: 'لا تُتلى',
              onChanged: reader.setPlayTitles,
            ),
          ),
          _Row(
            icon: 'user',
            label: 'التلاوة',
            onTap: library == null ? null : () => showReciterSheet(context, library),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
                  child: Text(reader.recording.reciterName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TzType.label.copyWith(color: c.ink2, fontWeight: FontWeight.w400)),
                ),
                if (library != null) ...[
                  const SizedBox(width: 8),
                  TzIcon('chev', size: 20, color: c.ink3),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── the pickers ──
  void _pickSpeed(BuildContext context) => showTzPicker(
        context,
        (_) => ListenableBuilder(
          listenable: reader,
          builder: (context, _) => TzPicker(
            title: 'السرعة',
            help: 'تُحفظ لكل تلاوة على حدة. تبقى نبرة الصوت كما هي.',
            child: OptionGrid<double>(
              semanticLabel: 'السرعة',
              options: {for (final v in kSpeedOptions) v: speedLabel(v)},
              selected: reader.speed,
              columns: 4,
              compact: true,
              onSelect: reader.setSpeed,
            ),
          ),
        ),
      );

  void _pickRepeat(BuildContext context, {required bool verse}) => showTzPicker(
        context,
        (_) => ListenableBuilder(
          listenable: reader,
          builder: (context, _) => TzPicker(
            title: verse ? 'تكرار البيت' : 'تكرار المقطع',
            help: verse
                ? 'يُعاد كل بيت بعدد المرات المختار، مع الفاصل بين كل مرة، ثم يُنتقل إلى التالي.'
                : 'يُعاد المقطع كله من أوله بعدد المرات المختار.',
            child: OptionGrid<int?>(
              semanticLabel: verse ? 'تكرار البيت' : 'تكرار المقطع',
              options: {for (final n in verse ? kVerseRepeatOptions : kSectionRepeatOptions) n: repeatLabel(n)},
              selected: verse ? reader.settings.verseRepeats : reader.settings.sectionRepeats,
              onSelect: verse ? reader.setVerseRepeats : reader.setSectionRepeats,
            ),
          ),
        ),
      );

  void _pickGap(BuildContext context) => showTzPicker(
        context,
        (_) => ListenableBuilder(
          listenable: reader,
          builder: (context, _) => TzPicker(
            title: 'الفاصل',
            help: 'سكتة بعد كل بيت، قبل إعادته أو الانتقال إلى التالي.',
            child: OptionGrid<int>(
              semanticLabel: 'الفاصل',
              options: {for (final ms in kGapOptionsMs) ms: gapLabel(ms)},
              selected: reader.settings.gapMs,
              columns: 4,
              compact: true,
              onSelect: reader.setGap,
            ),
          ),
        ),
      );
}

/// A glyph button: the glyph alone, in a target of at least 48 px (v2.css .ib).
class _Glyph extends StatelessWidget {
  final String icon, label;
  final double size, target;
  final Color color;
  final bool filled;
  final VoidCallback onTap;
  const _Glyph(
      {required this.icon,
      required this.label,
      required this.size,
      required this.color,
      required this.onTap,
      this.target = TzSize.touchTarget,
      this.filled = false});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox.square(
            dimension: target,
            child: Center(child: TzIcon(icon, filled: filled, size: size, color: color)),
          ),
        ),
      );
}

/// A row of the player's list (v2.css .prow): at least 52 px, a line above it.
class _Row extends StatelessWidget {
  final String icon, label;
  final Widget trailing;
  final VoidCallback? onTap;
  const _Row({required this.icon, required this.label, required this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final row = Container(
      constraints: const BoxConstraints(minHeight: 52),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.lineSoft))),
      child: Row(
        children: [
          TzIcon(icon, size: 20, color: c.ink3),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TzType.label.copyWith(color: c.ink))),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
    if (onTap == null) return row;
    return MergeSemantics(child: Semantics(button: true, child: InkWell(onTap: onTap, child: row)));
  }
}

/// A 1 px dashed line along the top edge (v2.css .upnext: border-top 1px dashed).
class _DashedLine extends CustomPainter {
  final Color color;
  const _DashedLine(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, 0.5), Offset((x + 3).clamp(0, size.width), 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedLine old) => old.color != color;
}

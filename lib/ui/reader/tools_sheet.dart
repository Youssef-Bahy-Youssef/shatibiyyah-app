// lib/ui/reader/tools_sheet.dart — «أدوات العرض والصوت» (features-v3: console-sheet, advanced-control-cards).
//
// One bottom sheet, three tabs:
//   العرض  — theme (dark / paper), page night mode, text mode, night brightness 40–100 %
//   الصوت  — the full player: big medallion, chapter, reciter, transport with stop, and
//            four tap-to-cycle cards (gap, speed, verse repeat, section repeat) whose
//            live counters also show on the medallion
//   المزيد — share the page, downloads, about (arriving in P5 / P7)
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/audio_library.dart';
import '../../data/settings_store.dart';
import '../design/tokens.g.dart';
import '../../utils/arabic.dart';
import '../design/pill_tabs.dart';
import '../design/taysir_colors.dart';
import '../share/share_sheet.dart';
import '../shell/about_screen.dart';
import '../shell/downloads_screen.dart';
import '../widgets/page_viewer.dart' show kMinBrightness, kMaxBrightness;
import 'reader_controller.dart';
import 'shamsa.dart';

enum ToolsTab { view, audio, more }

Future<void> showToolsSheet(BuildContext context, ReaderController reader, {ToolsTab tab = ToolsTab.view}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ToolsSheet(reader: reader, initialTab: tab),
    );

class ToolsSheet extends StatefulWidget {
  final ReaderController reader;
  final ToolsTab initialTab;
  const ToolsSheet({super.key, required this.reader, this.initialTab = ToolsTab.view});

  @override
  State<ToolsSheet> createState() => _ToolsSheetState();
}

class _ToolsSheetState extends State<ToolsSheet> {
  late ToolsTab _tab = widget.initialTab;
  ReaderController get r => widget.reader;

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AnimatedBuilder(
        animation: r,
        builder: (context, _) => Container(
          decoration: BoxDecoration(
            color: t.panel,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: t.line)),
          ),
          padding: EdgeInsets.fromLTRB(16, 10, 16, 20 + MediaQuery.of(context).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                    width: 36, height: 4, decoration: BoxDecoration(color: t.line, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 12),
              _Pills<ToolsTab>(
                values: ToolsTab.values,
                selected: _tab,
                label: (v) => switch (v) { ToolsTab.view => 'العرض', ToolsTab.audio => 'الصوت', ToolsTab.more => 'المزيد' },
                onSelect: (v) => setState(() => _tab = v),
              ),
              const SizedBox(height: 14),
              switch (_tab) {
                ToolsTab.view => _viewTab(t),
                ToolsTab.audio => _audioTab(t),
                ToolsTab.more => _moreTab(t),
              },
            ],
          ),
        ),
      ),
    );
  }

  // ── العرض ──
  Widget _viewTab(TaysirColors t) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('السمة', style: TzType.caption.copyWith(color: t.muted)),
          const SizedBox(height: 6),
          _Pills<ReaderTheme>(
            values: ReaderTheme.values,
            selected: r.theme,
            label: (v) => v == ReaderTheme.dark ? 'داكنة' : 'ورقية',
            onSelect: r.setTheme,
          ),
          const SizedBox(height: 10),
          _SwitchRow(icon: LucideIcons.moon, label: 'الوضع الليلي للصفحة', value: r.night, onChanged: r.setNight),
          _SwitchRow(icon: LucideIcons.alignJustify, label: 'العرض النصي', value: r.textMode, onChanged: r.setTextMode),
          Row(
            children: [
              Icon(LucideIcons.sun, size: 20, color: t.goldText),
              const SizedBox(width: 12),
              Expanded(child: Text('سطوع الصفحة ليلًا', style: TzType.label.copyWith(color: t.text))),
              _Round(
                icon: LucideIcons.minus,
                label: 'أخفت',
                onTap: r.brightness > kMinBrightness ? () => r.setBrightness(r.brightness - 10) : null,
              ),
              SizedBox(
                width: 52,
                child: Text('${ar(r.brightness)}٪',
                    textAlign: TextAlign.center, style: TzType.label.copyWith(color: t.text)),
              ),
              _Round(
                icon: LucideIcons.plus,
                label: 'أسطع',
                onTap: r.brightness < kMaxBrightness ? () => r.setBrightness(r.brightness + 10) : null,
              ),
            ],
          ),
        ],
      );

  // ── الصوت ──
  Widget _audioTab(TaysirColors t) {
    final c = r.chapter;
    final library = r.library;
    if (!r.audioAvailable) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (library != null) Center(child: _reciterChip(t, library)),
          const SizedBox(height: 12),
          Icon(LucideIcons.download, size: 32, color: t.goldText),
          const SizedBox(height: 10),
          Text('التلاوة غير منزّلة بعد',
              textAlign: TextAlign.center, style: TzType.head.copyWith(color: t.text)),
          const SizedBox(height: 4),
          Text('نزّل تلاوة ${r.recording.reciterName} لتسمع الأبيات؛ المتن والشروح تعمل دون تنزيل.',
              textAlign: TextAlign.center, style: TzType.label.copyWith(color: t.muted)),
          if (library != null) ...[
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(MaterialPageRoute<void>(builder: (_) => DownloadsScreen(library: library)));
              },
              style: FilledButton.styleFrom(
                backgroundColor: t.gold,
                minimumSize: const Size.fromHeight(48),
                shape: const StadiumBorder(),
              ),
              child: Text('التنزيلات', style: TzType.body.copyWith(color: t.onGold)),
            ),
          ],
        ]),
      );
    }
    final vr = r.settings.verseRepeats, sr = r.settings.sectionRepeats;
    String reps(int? n) => n == null ? '∞' : ar(n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: library == null ? _reciterLabel(t) : _reciterChip(t, library),
        ),
        const SizedBox(height: 10),
        Center(
          child: Shamsa(
            size: 100,
            verse: r.verse,
            playing: r.playing,
            chip: (vr == null || vr > 1) ? 'البيت ${ar(r.verseRepetition)}/${reps(vr)}' : null,
            ring: (sr == null || sr > 1) ? r.sectionRepetition / (sr ?? 1) : null,
          ),
        ),
        const SizedBox(height: 16),
        Text(c.shortLabel,
            textAlign: TextAlign.center, style: TzType.chapter.copyWith(color: t.text)),
        Text('الأبيات ${ar(c.fromVerse)}–${ar(c.toVerse)} · ${r.recording.reciterName}',
            textAlign: TextAlign.center, style: TzType.caption.copyWith(color: t.muted)),
        const SizedBox(height: 12),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _Round(icon: LucideIcons.skipBack, label: 'البيت السابق', onTap: r.previous, size: 52),
            const SizedBox(width: 10),
            _Round(icon: LucideIcons.square, label: 'إيقاف والعودة إلى البداية', onTap: r.stop, size: 52),
            const SizedBox(width: 10),
            _Round(
                icon: r.playing ? LucideIcons.pause : LucideIcons.play,
                label: r.playing ? 'إيقاف مؤقت' : 'تشغيل',
                onTap: r.playPause,
                size: 64,
                filled: true),
            const SizedBox(width: 10),
            _Round(icon: LucideIcons.skipForward, label: 'البيت التالي', onTap: r.next, size: 52),
          ]),
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.4,
          children: [
            _Card(
              icon: LucideIcons.hourglass,
              label: 'فاصل زمني',
              value: r.settings.gapMs == 0 ? 'بدون' : '${ar(r.settings.gapMs ~/ 1000)} ث',
              onTap: () => r.setGap(cycle(kGapOptionsMs, r.settings.gapMs)),
            ),
            _Card(
              icon: LucideIcons.gauge,
              label: 'سرعة التلاوة',
              value: '${ar(r.speed)}×',
              onTap: () => r.setSpeed(cycle(kSpeedOptions, r.speed)),
            ),
            _Card(
              icon: LucideIcons.repeat1,
              label: 'تكرار البيت',
              value: reps(vr),
              counter: (vr == null || vr > 1) ? '${ar(r.verseRepetition)}/${reps(vr)}' : null,
              onTap: () => r.setVerseRepeats(cycle(kVerseRepeatOptions, vr)),
            ),
            _Card(
              icon: LucideIcons.repeat,
              label: 'تكرار المقطع',
              value: reps(sr),
              counter: (sr == null || sr > 1) ? '${ar(r.sectionRepetition)}/${reps(sr)}' : null,
              onTap: () => r.setSectionRepeats(cycle(kSectionRepeatOptions, sr)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('المس البطاقة لتغيير القيمة · العدّادات تظهر على الشمسة أيضًا',
            textAlign: TextAlign.center, style: TzType.caption.copyWith(color: t.muted)),
      ],
    );
  }

  // ── المزيد ──
  Widget _reciterLabel(TaysirColors t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: t.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(LucideIcons.user, size: 16, color: t.goldText),
          const SizedBox(width: 6),
          Flexible(
            child: Text(r.recording.reciterName,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TzType.label.copyWith(color: t.text)),
          ),
          if (r.library != null) ...[
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronDown, size: 14, color: t.muted),
          ],
        ]),
      );

  /// The reciter's name; a tap opens «القارئ» (features-v3: «لسان الصوت ← شريحة اسم القارئ»).
  Widget _reciterChip(TaysirColors t, AudioLibrary library) => Semantics(
        button: true,
        label: 'القارئ: ${r.recording.reciterName}',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => showReciterSheet(context, library),
          child: _reciterLabel(t),
        ),
      );

  Widget _moreTab(TaysirColors t) {
    Widget row(IconData icon, String label, String sub, VoidCallback? onTap) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: onTap == null ? t.muted : t.goldText),
          title: Text(label, style: TzType.body.copyWith(color: onTap == null ? t.muted : t.text)),
          subtitle: Text(sub, style: TzType.caption.copyWith(color: t.muted)),
          enabled: onTap != null,
          onTap: onTap,
        );
    // A Material of its own: the sheet's coloured box would hide the rows' ink.
    return Material(
      type: MaterialType.transparency,
      child: Column(children: [
        row(LucideIcons.share2, 'مشاركة الصفحة', 'صورة الصفحة ${ar(r.page)} من المخطوط', () {
          Navigator.of(context).pop();
          sharePage(r.content, r.page);
        }),
        row(
          LucideIcons.download,
          'التنزيلات',
          'التلاوات: ${r.library == null ? '—' : megabytes(r.library!.bytesOnDevice)} على الجهاز',
          r.library == null
              ? null
              : () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  navigator.push(MaterialPageRoute<void>(builder: (_) => DownloadsScreen(library: r.library!)));
                },
        ),
        row(LucideIcons.info, 'حول', 'الإصدار والتعريف', () {
          final navigator = Navigator.of(context);
          navigator.pop();
          navigator.push(MaterialPageRoute<void>(builder: (_) => AboutScreen(reader: r)));
        }),
      ]),
    );
  }
}

class _Pills<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelect;
  const _Pills({required this.values, required this.selected, required this.label, required this.onSelect});

  @override
  Widget build(BuildContext context) => PillTabs<T>(
        options: {for (final v in values) v: label(v)},
        selected: selected,
        onSelect: onSelect,
        track: TaysirColors.of(context).bg,
      );
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({required this.icon, required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    // One item for a screen reader (the label with the switch), tappable as a whole.
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        child: SizedBox(
          height: 52,
          child: Row(children: [
            Icon(icon, size: 20, color: t.goldText),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TzType.label.copyWith(color: t.text))),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: t.onGold,
              activeTrackColor: t.gold,
              inactiveThumbColor: t.dim,
              inactiveTrackColor: t.line,
            ),
          ]),
        ),
      ),
    );
  }
}

class _Round extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;
  final bool filled;
  const _Round({required this.icon, required this.label, this.onTap, this.size = 44, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: filled
                  ? LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [t.goldBright, t.gold])
                  : null,
              border: filled ? null : Border.all(color: t.gold, width: 1.5),
            ),
            child: Icon(icon, size: size * 0.4, color: filled ? t.onGold : t.goldText),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? counter;
  final VoidCallback onTap;
  const _Card({required this.icon, required this.label, required this.value, this.counter, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return Semantics(
      button: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: t.panel2, borderRadius: BorderRadius.circular(18), border: Border.all(color: t.line)),
          child: Row(children: [
            Icon(icon, size: 22, color: t.goldText),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, style: TzType.caption.copyWith(color: t.muted)),
                  Text(value, style: TzType.head.copyWith(color: t.text)),
                ],
              ),
            ),
            if (counter != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: t.gold, borderRadius: BorderRadius.circular(999)),
                child: Text(counter!, style: TzType.caption.copyWith(color: t.onGold)),
              ),
          ]),
        ),
      ),
    );
  }
}

// lib/ui/widgets/console_panel.dart — the .cp-full content: brand header + ornament (desktop),
// session chip, mode tabs + panels (desktop), search (desktop), the gilt .console block
// (medallion + scrubber + transport), the advanced control cards, and the keep-controls pref
// row (mobile). Ported from index.html .cp-full + style.css.
import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../theme.dart';
import 'advanced_controls_sheet.dart';
import 'playback_controls.dart';
import 'progress_bar.dart';
import 'range_selector.dart';
import 'sync_controls.dart';
import 'verse_display.dart';
import 'verse_text_overlay.dart';

class ConsoleBody extends StatelessWidget {
  final AppController app;
  final bool wide; // desktop side panel vs mobile sheet
  const ConsoleBody({super.key, required this.app, required this.wide});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    if (wide) {
      children.add(_header());
      children.add(const SizedBox(height: 14));
      children.add(_ornament());
      children.add(const SizedBox(height: 14));
    }

    // session chip (Feature 1) — top of the console
    children.add(SessionChip(app: app));
    children.add(_gap());

    if (wide) {
      children.add(RangeSelector(app: app));
      children.add(_gap());
      children.add(VSearchBar(app: app));
      children.add(_gap());
    }

    // .console block
    children.add(_consoleBlock());
    children.add(_gap());

    // advanced control cards
    children.add(AdvancedControlCards(app: app));

    if (!wide) {
      children.add(const SizedBox(height: 11));
      children.add(_prefRow());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _gap() => SizedBox(height: wide ? 16 : 11);

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('الشاطبية',
                  style: kufi(
                      size: 32, weight: 700, color: C.goldBright, height: 1.1, letterSpacing: 0.5)),
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(style: naskh(size: 15.2, color: C.parchDim, height: 1.3), children: [
                  const TextSpan(text: 'حِرْزُ الأماني · بصوت '),
                  TextSpan(
                      text: 'الشيخ محمد عتيق',
                      style: naskh(size: 15.2, weight: FontWeight.w600, color: C.gold)),
                ]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ornament() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [
                Color(0x00965F0D),
                Color(0xA6965F0D),
                Color(0xA6FFAB2E),
                Color(0xA6965F0D),
                Color(0x00965F0D),
              ], stops: [
                0.0,
                0.38,
                0.5,
                0.62,
                1.0
              ]),
            ),
          ),
        ),
        const SizedBox(width: 11),
        const Icon(Icons.star, size: 17, color: C.gold),
        const SizedBox(width: 11),
        Expanded(
          child: Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [
                Color(0x00965F0D),
                Color(0xA6965F0D),
                Color(0xA6FFAB2E),
                Color(0xA6965F0D),
                Color(0x00965F0D),
              ], stops: [
                0.0,
                0.38,
                0.5,
                0.62,
                1.0
              ]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _consoleBlock() {
    return Container(
      padding: wide
          ? const EdgeInsets.fromLTRB(16, 18, 16, 20)
          : const EdgeInsets.fromLTRB(13, 13, 13, 15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x6B3F2F15), Color(0x8C241A0C)],
        ),
        border: Border.all(color: C.line),
        borderRadius: BorderRadius.circular(R.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          VerseDisplay(app: app, compact: !wide),
          SizedBox(height: wide ? 13 : 11),
          ProgressBar(app: app),
          SizedBox(height: wide ? 13 : 11),
          PlaybackControls(app: app, compact: !wide),
        ],
      ),
    );
  }

  Widget _prefRow() {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) => Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: C.lineSoft)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('إبقاء عناصر التحكم ظاهرة',
                      style: naskh(size: 16.96, color: C.parch)),
                  const SizedBox(height: 1),
                  Text('لا تُخفى عناصر التحكم تلقائيًا',
                      style: ui(size: 10.88, color: C.muted)),
                ],
              ),
            ),
            ToggleSwitch(
              value: app.keepControlsVisible,
              onChanged: app.setKeepControls,
            ),
          ],
        ),
      ),
    );
  }
}

/// CSS .toggle — pill switch, gold-filled when on, knob slides.
class ToggleSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const ToggleSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 50,
        height: 30,
        decoration: BoxDecoration(
          gradient: value
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [C.goldBright, C.gold])
              : null,
          color: value ? null : C.raised,
          border: Border.all(color: value ? Colors.transparent : C.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: const Cubic(.22, .61, .36, 1),
          alignment: value ? Alignment.centerLeft : Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.all(3),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? C.onGold : C.parchDim,
            ),
          ),
        ),
      ),
    );
  }
}

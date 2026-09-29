// lib/ui/widgets/range_selector.dart — the باب/نطاق/كل المتن selector body: mode tabs +
// the active panel (chapter list · from/to steppers · full-متن info). Ported from
// index.html panels (#panel-chapter/#panel-range/#panel-full) + app.js range wiring.
import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../theme.dart';
import '../../utils/arabic.dart' show ar, normDigits;
import 'chapter_selector.dart';
import 'mode_tabs.dart';

class RangeSelector extends StatelessWidget {
  final AppController app;
  final bool stickyTabs; // mobile sheet: tabs stick to the top, chapter list scrolls
  final ScrollController? chapterScroll;
  const RangeSelector({
    super.key,
    required this.app,
    this.stickyTabs = false,
    this.chapterScroll,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final mode = app.audio.mode;
        final tabs = ModeTabs(app: app);
        final panel = _panel(mode);
        if (stickyTabs) {
          // chapter mode: tabs fixed, list fills remaining height & scrolls
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: C.ink2,
                padding: const EdgeInsets.only(top: 6, bottom: 8),
                child: tabs,
              ),
              if (mode == 'chapter')
                Expanded(
                  child: _ChapterLabel(
                    child: ChapterSelector(app: app, scrollController: chapterScroll),
                  ),
                )
              else
                panel,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            tabs,
            const SizedBox(height: 14),
            panel,
          ],
        );
      },
    );
  }

  Widget _panel(String mode) {
    switch (mode) {
      case 'chapter':
        return _ChapterLabel(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 440),
            child: ChapterSelector(app: app, scrollController: chapterScroll),
          ),
        );
      case 'range':
        return _RangeRow(app: app);
      default:
        return _FullInfo(app: app);
    }
  }
}

class _ChapterLabel extends StatelessWidget {
  final Widget child;
  const _ChapterLabel({required this.child});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 7, right: 2, left: 2),
          child: Text('اختر الباب — اضغط للانتقال إليه',
              style: kufi(size: 13.76, weight: 500, color: C.muted)),
        ),
        Flexible(child: child),
      ],
    );
  }
}

class _FullInfo extends StatelessWidget {
  final AppController app;
  const _FullInfo({required this.app});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: C.panel2,
        border: Border.all(color: C.line),
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Text.rich(
        TextSpan(
          style: naskh(size: 19.2, color: C.parchDim),
          children: [
            const TextSpan(text: 'المتن كاملًا — من البيت '),
            TextSpan(
                text: ar(1),
                style: naskh(size: 19.2, weight: FontWeight.w600, color: C.goldBright)),
            const TextSpan(text: ' إلى البيت '),
            TextSpan(
                text: ar(app.data.lastVerse),
                style: naskh(size: 19.2, weight: FontWeight.w600, color: C.goldBright)),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _RangeRow extends StatelessWidget {
  final AppController app;
  const _RangeRow({required this.app});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
                child: _Stepper(
                    app: app,
                    which: 'from',
                    label: 'من البيت',
                    value: app.audio.fromVerse)),
            const SizedBox(width: 12),
            Expanded(
                child: _Stepper(
                    app: app,
                    which: 'to',
                    label: 'إلى البيت',
                    value: app.audio.toVerse)),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(top: 0, left: 2, right: 2),
          child: Text('اختر بيتًا بين ${ar(1)} و ${ar(1173)}',
              textAlign: TextAlign.center,
              style: ui(size: 11.52, color: C.muted2)),
        ),
      ],
    );
  }
}

class _Stepper extends StatefulWidget {
  final AppController app;
  final String which;
  final String label;
  final int value;
  const _Stepper(
      {required this.app,
      required this.which,
      required this.label,
      required this.value});
  @override
  State<_Stepper> createState() => _StepperState();
}

class _StepperState extends State<_Stepper> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.value.toString());
  final _focus = FocusNode();

  @override
  void didUpdateWidget(covariant _Stepper old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value.toString() != _ctrl.text) {
      _ctrl.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final v = int.tryParse(normDigits(_ctrl.text));
    final f = widget.which == 'from'
        ? (v ?? widget.app.audio.fromVerse)
        : widget.app.audio.fromVerse;
    final t = widget.which == 'to'
        ? (v ?? widget.app.audio.toVerse)
        : widget.app.audio.toVerse;
    widget.app.commitRange(f, t);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: C.panel2,
        border: Border.all(color: C.line),
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.label, style: kufi(size: 13.76, weight: 500, color: C.muted)),
          const SizedBox(height: 7),
          Row(
            children: [
              _stepBtn('−', () => widget.app.stepRange(widget.which, -1)),
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    onSubmitted: (_) => _commit(),
                    onTapOutside: (_) {
                      _focus.unfocus();
                      _commit();
                    },
                    style: ui(
                        size: 22.4,
                        weight: FontWeight.w600,
                        color: C.parch,
                        tabular: true),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              _stepBtn('+', () => widget.app.stepRange(widget.which, 1)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(String glyph, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: C.raised,
          border: Border.all(color: C.line),
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Text(glyph,
            style: ui(size: 24, color: C.goldBright, height: 1)),
      ),
    );
  }
}

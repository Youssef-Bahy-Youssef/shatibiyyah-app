// lib/ui/widgets/advanced_controls_sheet.dart — the 2×2 advanced control cards (.controls /
// .ctrl-card) + the picker bottom sheet (.sheet) they open. Ported from index.html
// (data-sheet="pause|speed|verse|section") + app.js SHEETS{} + style.css.
import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../theme.dart';
import '../../utils/arabic.dart';
import 'sheet_scaffold.dart';

class AdvancedControlCards extends StatelessWidget {
  final AppController app;
  const AdvancedControlCards({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) => Column(
        children: [
          Row(children: [
            Expanded(
                child: _card('⏱', 'فاصل زمني', app.valPause, SheetType.pause)),
            const SizedBox(width: 10),
            Expanded(
                child: _card('🎚', 'سرعة التلاوة', app.valSpeed, SheetType.speed)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: _card('🔁', 'تكرار البيت', app.valVerse, SheetType.verse)),
            const SizedBox(width: 10),
            Expanded(
                child:
                    _card('🔁', 'تكرار المقطع', app.valSection, SheetType.section)),
          ]),
        ],
      ),
    );
  }

  Widget _card(String ico, String label, String value, SheetType type) {
    return GestureDetector(
      onTap: () => app.openPicker(type),
      child: Container(
        constraints: const BoxConstraints(minHeight: R.tap),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x803F2F15), Color(0x8021180C)],
          ),
          border: Border.all(color: C.line),
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Row(
          children: [
            Text(ico, style: const TextStyle(fontSize: 20.8)),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kufi(size: 13.12, weight: 500, color: C.muted)),
                  const SizedBox(height: 1),
                  Text(value,
                      style: naskh(
                          size: 20.8,
                          weight: FontWeight.w600,
                          color: C.goldBright,
                          height: 1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The picker sheet (.sheet) — chips for the active option set. Ported from app.js openSheet().
class PickerSheet extends StatelessWidget {
  final AppController app;
  const PickerSheet({super.key, required this.app});

  String _chipLabel(SheetType type, num v) {
    if (v == double.infinity) return '∞';
    if (type == SheetType.speed) return '${ar(v)}×';
    if (type == SheetType.pause) return v == 0 ? 'بدون' : '${ar(v)} ث';
    return ar(v);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) => SheetScaffold(
        open: app.pickerOpen,
        onClose: app.closePicker,
        title: app.pickerTitle(),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: app.pickerOptions().map((v) {
            final on = v == app.pickerCurrent();
            final isInf = v == double.infinity;
            return GestureDetector(
              onTap: () {
                app.pickerSet(v);
                Future.delayed(const Duration(milliseconds: 130), app.closePicker);
              },
              child: Container(
                constraints:
                    const BoxConstraints(minWidth: 62, minHeight: R.tap),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  gradient: on
                      ? const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [C.goldBright, C.gold])
                      : null,
                  color: on ? null : C.panel2,
                  border: Border.all(color: on ? Colors.transparent : C.line),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: on
                      ? const [
                          BoxShadow(
                              color: Color(0xD9FFAB2E),
                              blurRadius: 20,
                              offset: Offset(0, 8),
                              spreadRadius: -10)
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  _chipLabel(app.pickerType, v),
                  style: naskh(
                    size: isInf ? 27.2 : 21.6,
                    weight: FontWeight.w600,
                    color: on ? C.onGold : C.parch,
                    height: 1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

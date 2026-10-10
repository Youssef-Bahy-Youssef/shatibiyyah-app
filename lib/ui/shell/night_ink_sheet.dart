// lib/ui/shell/night_ink_sheet.dart — «لون الحبر الليلي» (item 3.6, ADR 0020;
// handoff settings-picker): the five offered inks as a radiogroup, each on a
// crop of the real page at night. Choosing one applies at once (it is stored,
// and the night page, the chosen-verse ring and the rubric follow); «تم» only
// closes the sheet.
import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import '../design/components/night_ink_option.dart';
import '../design/components/tz_picker.dart';
import '../design/tokens.g.dart';
import '../reader/reader_controller.dart';

Future<void> showNightInkSheet(BuildContext context, ReaderController reader) =>
    showTzPicker(context, (context) => NightInkSheet(reader: reader));

class NightInkSheet extends StatelessWidget {
  final ReaderController reader;
  const NightInkSheet({super.key, required this.reader});

  @override
  Widget build(BuildContext context) => TzPicker(
        title: TzNightPage.pickerTitle,
        help: TzNightPage.pickerHelp,
        child: ValueListenableBuilder<TzNightInk>(
          valueListenable: appNightInk,
          builder: (context, chosen, _) => Semantics(
            container: true,
            explicitChildNodes: true,
            label: TzNightPage.pickerTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, ink) in TzNightPage.inks.indexed) ...[
                  if (i > 0) const SizedBox(height: 8),
                  NightInkOption(
                    ink: ink,
                    selected: ink.id == chosen.id,
                    isDefault: ink.id == TzNightPage.defaultInk,
                    onTap: () => reader.setNightInk(ink),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

// lib/ui/shell/night_ink_sheet.dart — «لون الحبر الليلي» (item 3.6, ADR 0020;
// handoff settings-picker): the five offered inks as a radiogroup, each on a
// crop of the real page at night. Choosing one applies at once (it is stored,
// and the night page, the chosen-verse ring and the rubric follow); «تم» only
// closes the sheet.
import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import '../design/components/night_ink_option.dart';
import '../design/components/tz_button.dart';
import '../design/components/tz_sheet.dart';
import '../design/tokens.g.dart';
import '../design/tz_theme.dart';
import '../reader/reader_controller.dart';

Future<void> showNightInkSheet(BuildContext context, ReaderController reader) =>
    showPickerSheet(context, (context) => NightInkSheet(reader: reader));

/// A picker sheet over the whole app (the dock too), on the theme's scrim.
Future<void> showPickerSheet(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: builder,
    );

class NightInkSheet extends StatelessWidget {
  final ReaderController reader;
  const NightInkSheet({super.key, required this.reader});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final media = MediaQuery.of(context);
    return TzSheet.picker(
      child: ConstrainedBox(
        // The sheet's own grab and padding (55 px) stay on screen under the status bar.
        constraints: BoxConstraints(maxHeight: media.size.height - media.viewPadding.top - 55),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Text(TzNightPage.pickerTitle, style: TzType.title.copyWith(color: c.ink)),
            Text(TzNightPage.pickerHelp, style: TzType.label.copyWith(color: c.ink3)),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
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
              ),
            ),
            const SizedBox(height: 12),
            TzButton.primary(label: 'تم', onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }
}

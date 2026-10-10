// lib/ui/reader/display_sheet.dart — «العرض» (item 3.8, ADR 0021; handoff
// textmode-display): the page or the text, and the text's size as six steps
// with a live sample (the reader's own verse at the chosen size). It opens from
// the top bar's «العرض» in either view, and from «حجم نص المتن» in the settings.
//
// Under the sample, the switch for the rubric ink («إبراز رموز القراء وأسمائهم»):
// the reader names and symbols of the span data (item 2.3), shown unless hidden.
import 'package:flutter/material.dart';

import '../../data/settings_store.dart';
import '../../utils/arabic.dart';
import '../design/components/min_segmented.dart';
import '../design/components/text_size_grid.dart';
import '../design/components/tz_picker.dart';
import '../design/components/tz_switch.dart';
import '../design/components/verse_unit.dart';
import '../design/tokens.g.dart';
import '../design/tz_icon.dart';
import '../design/tz_theme.dart';
import 'reader_controller.dart';
import 'verse_rubrics.dart';

Future<void> showDisplaySheet(BuildContext context, ReaderController reader) =>
    showTzPicker(context, (_) => DisplaySheet(reader: reader));

class DisplaySheet extends StatelessWidget {
  final ReaderController reader;
  const DisplaySheet({super.key, required this.reader});

  static const sampleKey = ValueKey('display-sample');
  static const rubricRowKey = ValueKey('display-rubric-row');

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: reader,
        builder: (context, _) {
          final c = TzTheme.of(context).colors;
          final verse = reader.content.matn.verse(reader.verse);
          return TzPicker(
            title: 'العرض',
            doneGap: 0, // the switch row ends the content
            titleTrailing: MinSegmented<bool>(
              semanticLabel: 'العرض',
              options: const {false: 'الصفحة', true: 'النص'},
              selected: reader.textMode,
              onSelect: reader.setTextMode,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('حجم نص المتن', style: TzType.label.copyWith(color: c.ink)),
                const SizedBox(height: 10),
                TextSizeGrid(scales: kTextScaleOptions, selected: reader.textScale, onSelect: reader.setTextScale),
                const SizedBox(height: 14),
                Container(
                  key: sampleKey,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: c.bg,
                    borderRadius: BorderRadius.circular(TzRadius.control),
                    border: Border.all(color: c.lineSoft),
                  ),
                  child: VerseUnit(
                    number: ar(reader.verse),
                    first: verse.firstHemistich,
                    second: verse.secondHemistich,
                    rubrics: reader.showRubric ? verseRubrics(reader.content, reader.verse) : const [],
                    fontSize: reader.verseSize,
                  ),
                ),
                const SizedBox(height: 4),
                // v2.css .prow: 52 px, the icon, the label, the switch with its word.
                ConstrainedBox(
                  key: rubricRowKey,
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Row(
                    children: [
                      TzIcon('mic', size: 20, color: c.ink3),
                      const SizedBox(width: 12),
                      Expanded(child: Text('إبراز رموز القراء وأسمائهم', style: TzType.label.copyWith(color: c.ink))),
                      const SizedBox(width: 12),
                      TzSwitch(
                        value: reader.showRubric,
                        onWord: 'ظاهر',
                        offWord: 'مخفي',
                        semanticLabel: 'إبراز رموز القراء',
                        onChanged: reader.setShowRubric,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
}

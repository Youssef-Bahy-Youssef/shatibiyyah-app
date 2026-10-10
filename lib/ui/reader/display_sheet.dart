// lib/ui/reader/display_sheet.dart — «العرض» (item 3.8, ADR 0021; handoff
// textmode-display): the page or the text, and the text's size as six steps
// with a live sample (the reader's own verse at the chosen size). It opens from
// the top bar's «العرض» in either view, and from «حجم نص المتن» in the settings.
//
// The design's switch for the rubric ink («إبراز رموز القراء وأسمائهم») joins
// it with the span data (item 2.3): text mode shows no rubric until then.
import 'package:flutter/material.dart';

import '../../data/settings_store.dart';
import '../../utils/arabic.dart';
import '../design/components/min_segmented.dart';
import '../design/components/text_size_grid.dart';
import '../design/components/tz_picker.dart';
import '../design/components/verse_unit.dart';
import '../design/tokens.g.dart';
import '../design/tz_theme.dart';
import 'reader_controller.dart';

Future<void> showDisplaySheet(BuildContext context, ReaderController reader) =>
    showTzPicker(context, (_) => DisplaySheet(reader: reader));

class DisplaySheet extends StatelessWidget {
  final ReaderController reader;
  const DisplaySheet({super.key, required this.reader});

  static const sampleKey = ValueKey('display-sample');

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: reader,
        builder: (context, _) {
          final c = TzTheme.of(context).colors;
          final verse = reader.content.matn.verse(reader.verse);
          return TzPicker(
            title: 'العرض',
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
                    fontSize: reader.verseSize,
                  ),
                ),
              ],
            ),
          );
        },
      );
}

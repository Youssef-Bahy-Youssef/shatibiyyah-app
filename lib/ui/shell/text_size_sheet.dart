// lib/ui/shell/text_size_sheet.dart — «حجم نص المتن» from «الإعدادات»: the size
// steps of the matn's text (the same control text mode's «العرض» sheet carries).
import 'package:flutter/material.dart';

import '../../data/settings_store.dart';
import '../design/components/text_size_grid.dart';
import '../design/components/tz_button.dart';
import '../design/components/tz_sheet.dart';
import '../design/tokens.g.dart';
import '../design/tz_theme.dart';
import '../reader/reader_controller.dart';
import 'night_ink_sheet.dart' show showPickerSheet;

Future<void> showTextSizeSheet(BuildContext context, ReaderController reader) => showPickerSheet(
      context,
      (context) => TzSheet.picker(
        child: ListenableBuilder(
          listenable: reader,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Text('حجم نص المتن', style: TzType.title.copyWith(color: TzTheme.of(context).colors.ink)),
              const SizedBox(height: 10),
              TextSizeGrid(scales: kTextScaleOptions, selected: reader.textScale, onSelect: reader.setTextScale),
              const SizedBox(height: 12),
              TzButton.primary(label: 'تم', onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    );

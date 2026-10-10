// lib/ui/shell/text_size_sheet.dart — «حجم نص المتن» from «الإعدادات»: the size
// steps of the matn's text (the same control text mode's «العرض» sheet carries).
import 'package:flutter/material.dart';

import '../../data/settings_store.dart';
import '../design/components/text_size_grid.dart';
import '../design/components/tz_picker.dart';
import '../reader/reader_controller.dart';

Future<void> showTextSizeSheet(BuildContext context, ReaderController reader) => showTzPicker(
      context,
      (context) => TzPicker(
        title: 'حجم نص المتن',
        child: ListenableBuilder(
          listenable: reader,
          builder: (context, _) =>
              TextSizeGrid(scales: kTextScaleOptions, selected: reader.textScale, onSelect: reader.setTextScale),
        ),
      ),
    );

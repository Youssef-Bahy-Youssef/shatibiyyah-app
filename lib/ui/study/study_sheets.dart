// lib/ui/study/study_sheets.dart — «المرجع» and «ملاحظة» (features-v3 bookmarks,
// verse-notes), opened from the verse menu or, for a run of verses, the selection bar.
import 'package:flutter/material.dart';

import '../../app/personal_data.dart';
import '../../data/app_content.dart';
import '../../data/user_store.dart';
import '../../theme.dart' show kufi, naskh;
import '../../utils/arabic.dart';
import '../design/taysir_colors.dart';

Widget _sheetFrame(BuildContext context, List<Widget> children) {
  final t = TaysirColors.of(context);
  return Directionality(
    textDirection: TextDirection.rtl,
    child: Container(
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: t.line)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, 20 + MediaQuery.of(context).padding.bottom + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(color: t.line, borderRadius: BorderRadius.circular(999)),
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}

/// «البيت ٢٢٩، باب …» or «الأبيات ٢٢٦–٢٣٤، باب …» («،» after the number: a «·» there
/// reads as «٠»).
String studyTarget(AppContent content, int from, int? to) {
  final chapter = content.matn.chapterOfVerse(from).shortLabel;
  return to == null || to == from ? 'البيت ${ar(from)}، $chapter' : 'الأبيات ${isolatedRange(from, to)}، $chapter';
}

/// «المرجع»: colour and tag for [from] (…[to]); [onDone] receives the notice to show.
Future<void> showBookmarkSheet(
  BuildContext context, {
  required PersonalData personal,
  required AppContent content,
  required int from,
  int? to,
  required void Function(String notice) onDone,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BookmarkSheet(personal: personal, content: content, from: from, to: to, onDone: onDone),
    );

class _BookmarkSheet extends StatefulWidget {
  final PersonalData personal;
  final AppContent content;
  final int from;
  final int? to;
  final void Function(String) onDone;
  const _BookmarkSheet({required this.personal, required this.content, required this.from, this.to, required this.onDone});

  @override
  State<_BookmarkSheet> createState() => _BookmarkSheetState();
}

class _BookmarkSheetState extends State<_BookmarkSheet> {
  late final Bookmark? _existing = widget.personal.bookmarkAt(widget.from, to: widget.to);
  late BookmarkColor _color = _existing?.color ?? BookmarkColor.gold;
  late BookmarkTag _tag = _existing?.tag ?? BookmarkTag.hifz;

  String get _what => widget.to == null || widget.to == widget.from
      ? 'البيت ${ar(widget.from)}'
      : 'الأبيات ${isolatedRange(widget.from, widget.to!)}';

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    await widget.personal.saveBookmark(widget.from, to: widget.to, color: _color, tag: _tag);
    navigator.pop();
    widget.onDone('حُفظ المرجع على $_what');
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    await widget.personal.deleteBookmark(widget.from, to: widget.to);
    navigator.pop();
    widget.onDone('أُزيل المرجع');
  }

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return _sheetFrame(context, [
      Text('المرجع', style: kufi(size: 18, weight: 600, color: t.text)),
      Text(studyTarget(widget.content, widget.from, widget.to), style: naskh(size: 16, color: t.dim, height: 1.7)),
      const SizedBox(height: 12),
      Text('اللون', style: kufi(size: 12.5, weight: 400, color: t.muted)),
      const SizedBox(height: 8),
      Row(
        children: [
          for (final c in BookmarkColor.values)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: Semantics(
                button: true,
                selected: c == _color,
                label: 'لون',
                child: GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kBookmarkColors[c],
                      boxShadow: c == _color
                          ? [BoxShadow(color: t.panel, spreadRadius: 3), BoxShadow(color: t.gold, spreadRadius: 5)]
                          : null,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 14),
      Text('الوسم', style: kufi(size: 12.5, weight: 400, color: t.muted)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          for (final tag in BookmarkTag.values)
            ChoiceChip(
              label: Text(kBookmarkTagLabels[tag]!,
                  style: kufi(size: 14, weight: 500, color: tag == _tag ? t.onGold : t.text)),
              selected: tag == _tag,
              showCheckmark: false,
              selectedColor: t.gold,
              backgroundColor: t.panel2,
              side: BorderSide(color: t.line),
              shape: const StadiumBorder(),
              onSelected: (_) => setState(() => _tag = tag),
            ),
        ],
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: t.gold,
                minimumSize: const Size.fromHeight(50),
                shape: const StadiumBorder(),
              ),
              // Not just «حفظ»: that is also the first tag, right above.
              child: Text('حفظ المرجع', style: kufi(size: 15.5, weight: 600, color: t.onGold)),
            ),
          ),
          if (_existing != null) ...[
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: _delete,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(96, 50),
                side: BorderSide(color: t.line),
                shape: const StadiumBorder(),
              ),
              child: Text('حذف', style: kufi(size: 15, weight: 500, color: t.warn)),
            ),
          ],
        ],
      ),
    ]);
  }
}

/// «ملاحظة على البيت N»: one note per verse; saving it empty removes it.
Future<void> showNoteSheet(
  BuildContext context, {
  required PersonalData personal,
  required AppContent content,
  required int verse,
  required void Function(String notice) onDone,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NoteSheet(personal: personal, content: content, verse: verse, onDone: onDone),
    );

class _NoteSheet extends StatefulWidget {
  final PersonalData personal;
  final AppContent content;
  final int verse;
  final void Function(String) onDone;
  const _NoteSheet({required this.personal, required this.content, required this.verse, required this.onDone});

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  late final _field = TextEditingController(text: widget.personal.noteFor(widget.verse)?.body ?? '');

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final had = widget.personal.noteFor(widget.verse) != null;
    await widget.personal.saveNote(widget.verse, _field.text);
    navigator.pop();
    final empty = _field.text.trim().isEmpty;
    if (!empty || had) widget.onDone(empty ? 'حُذفت الملاحظة' : 'حُفظت الملاحظة');
  }

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return _sheetFrame(context, [
      Text('ملاحظة على البيت ${ar(widget.verse)}', style: kufi(size: 18, weight: 600, color: t.text)),
      Text(widget.content.matn.chapterOfVerse(widget.verse).shortLabel,
          style: naskh(size: 16, color: t.dim, height: 1.7)),
      const SizedBox(height: 10),
      TextField(
        controller: _field,
        autofocus: true,
        minLines: 4,
        maxLines: 8,
        style: naskh(size: 18, color: t.text, height: 1.7),
        cursorColor: t.gold,
        decoration: InputDecoration(
          hintText: 'اكتب ملاحظتك…',
          hintStyle: naskh(size: 17, color: t.muted),
          filled: true,
          fillColor: t.panel2,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: t.line)),
          enabledBorder:
              OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: t.line)),
          focusedBorder:
              OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: t.gold)),
        ),
      ),
      const SizedBox(height: 14),
      FilledButton(
        onPressed: _save,
        style: FilledButton.styleFrom(
          backgroundColor: t.gold,
          minimumSize: const Size.fromHeight(50),
          shape: const StadiumBorder(),
        ),
        child: Text('حفظ', style: kufi(size: 15.5, weight: 600, color: t.onGold)),
      ),
    ]);
  }
}

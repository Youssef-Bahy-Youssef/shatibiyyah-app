// lib/ui/shell/rumuz_screen.dart — «رموز القراء» (features-v3 rumuz-legend).
//
// Three tabs: the letters (أبجد هوز حطي كلمن صعفض قرست, verse 45) as a grid of
// code and reader; the group letters (ث خ ذ ظ غ ش, verses 49–52); the code words
// (صحبة … حصن, verses 52–55), each with the readers it names and its source verse.
// A source verse opens the reader there.
import 'package:flutter/material.dart';

import '../../data/rumuz_repository.dart';
import '../design/tokens.g.dart';
import '../../utils/arabic.dart';
import '../design/pill_tabs.dart';
import '../design/taysir_colors.dart';
import '../reader/reader_controller.dart';
import 'app_shell.dart';
import 'shell_page.dart';

class RumuzScreen extends StatefulWidget {
  final ReaderController reader;
  const RumuzScreen({super.key, required this.reader});

  @override
  State<RumuzScreen> createState() => _RumuzScreenState();
}

class _RumuzScreenState extends State<RumuzScreen> {
  RamzKind _tab = RamzKind.letter;

  RumuzRepository get _rumuz => widget.reader.content.rumuz;

  void _openVerse(int verse) => AppShell.openVerse(context, widget.reader, verse);

  /// The letters as the poem groups them, an imam and his two transmitters per
  /// word: «أبج دهز حطي كلم نصع فضق رست».
  static String _triples(List<Ramz> letters) => [
        for (var i = 0; i < letters.length; i += 3)
          letters.skip(i).take(3).map((r) => r.code).join(),
      ].join(' ');

  String _verses(Ramz r) => r.fromVerse == r.toVerse ? ar(r.fromVerse) : isolatedRange(r.fromVerse, r.toVerse);

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    final list = _rumuz.ofKind(_tab);
    return ShellPage(
      title: 'رموز القراء',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          PillTabs<RamzKind>(
            options: const {RamzKind.letter: 'الحروف', RamzKind.groupLetter: 'الجماعات', RamzKind.word: 'الكلمات'},
            selected: _tab,
            onSelect: (k) => setState(() => _tab = k),
          ),
          const SizedBox(height: 14),
          if (list.isEmpty)
            const SizedBox.shrink()
          else if (_tab == RamzKind.letter) ...[
            InkWell(
              onTap: () => _openVerse(list.first.fromVerse),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('${_triples(list)}، البيت ${_verses(list.first)}',
                      style: TzType.caption.copyWith(color: t.muted)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.9,
              children: [for (final r in list) _letter(t, r)],
            ),
          ] else ...[
            Text(
              'الأبيات ${isolatedRange(list.first.fromVerse, list.last.toVerse)}',
              style: TzType.caption.copyWith(color: t.muted),
            ),
            const SizedBox(height: 8),
            for (final r in list) _row(t, r),
          ],
        ],
      ),
    );
  }

  Widget _letter(TaysirColors t, Ramz r) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: t.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.line),
        ),
        child: Row(
          children: [
            Text(r.code, style: TzType.hero.copyWith(color: t.goldText)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(r.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TzType.label.copyWith(color: t.text)),
            ),
          ],
        ),
      );

  Widget _row(TaysirColors t, Ramz r) => InkWell(
        onTap: () => _openVerse(r.fromVerse),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
          child: Row(
            children: [
              SizedBox(
                width: 72,
                child: Text(r.code, style: TzType.hero.copyWith(color: t.goldText)),
              ),
              Expanded(child: Text(r.label, style: TzType.label.copyWith(color: t.text))),
              Text('البيت ${_verses(r)}', style: TzType.caption.copyWith(color: t.muted)),
            ],
          ),
        ),
      );
}

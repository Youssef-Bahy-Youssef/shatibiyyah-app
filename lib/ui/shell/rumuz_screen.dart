// lib/ui/shell/rumuz_screen.dart — «رموز القراء» (features-v3 rumuz-legend).
//
// Three tabs, every symbol in the rubric ink and in its frame (ADR 0024):
//   - the letters (أبجد هوز حطي كلمن صعفض قرست, verse 45): one row per reader,
//     numbered in a khatam, his letter and then his two transmitters';
//   - the group letters (ث خ ذ ظ غ ش, verses 49–52) and the code words
//     (صحبة … حصن, verses 52–55): a row each, with who it stands for, the
//     readers a collective name gathers, and its source verse.
// A source verse opens the reader there. Opened from a symbol's tip, the screen
// starts on that symbol's tab with it marked.
import 'package:flutter/material.dart';

import '../../data/rumuz_repository.dart';
import '../../utils/arabic.dart';
import '../design/components/khatam.dart';
import '../design/components/symbol_chip.dart';
import '../design/pill_tabs.dart';
import '../design/tokens.g.dart';
import '../design/tz_icon.dart';
import '../design/tz_theme.dart';
import '../reader/reader_controller.dart';
import 'app_shell.dart';
import 'shell_page.dart';

class RumuzScreen extends StatefulWidget {
  final ReaderController reader;

  /// The symbol the student came from (its code in the list): its tab opens, with it marked.
  final String? focus;
  const RumuzScreen({super.key, required this.reader, this.focus});

  static const sourceKey = ValueKey('rumuz-source');

  @override
  State<RumuzScreen> createState() => _RumuzScreenState();
}

class _RumuzScreenState extends State<RumuzScreen> {
  late RamzKind _tab = _rumuz.byCode(widget.focus ?? '')?.kind ?? RamzKind.letter;
  final _focused = GlobalKey();

  RumuzRepository get _rumuz => widget.reader.content.rumuz;

  @override
  void initState() {
    super.initState();
    if (widget.focus == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final at = _focused.currentContext;
      if (at != null) Scrollable.ensureVisible(at, alignment: 0.3);
    });
  }

  void _openVerse(int verse) => AppShell.openVerse(context, widget.reader, verse);

  /// The letters as the poem groups them, an imam and his two transmitters per
  /// word: «أبج دهز حطي كلم نصع فضق رست».
  static String _triples(List<Ramz> letters) => [
        for (var i = 0; i < letters.length; i += 3)
          letters.skip(i).take(3).map((r) => r.code).join(),
      ].join(' ');

  String _verses(Ramz r) => r.fromVerse == r.toVerse ? ar(r.fromVerse) : isolatedRange(r.fromVerse, r.toVerse);

  /// The readers a collective name gathers («الكوفيون»: عاصم، حمزة، الكسائي); null when the name lists them already.
  String? _members(Ramz r) {
    final names = [for (final id in r.readerIds) ?_rumuz.reader(id)?.name];
    return names.every(r.label.contains) ? null : names.join('، ');
  }

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final list = _rumuz.ofKind(_tab);
    final caption = TzType.caption.copyWith(color: c.ink3);
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
          const SizedBox(height: 6),
          if (list.isEmpty)
            const SizedBox.shrink()
          else if (_tab == RamzKind.letter) ...[
            _source('${_triples(list)}، البيت ${_verses(list.first)}', list.first.fromVerse, c),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 34, bottom: 4),
              child: Row(
                children: [
                  Expanded(child: Text('القارئ', style: caption)),
                  Expanded(flex: 2, child: Text('راوياه', style: caption)),
                ],
              ),
            ),
            for (var i = 0; i + 2 < list.length; i += 3) _reader(c, i ~/ 3 + 1, list.sublist(i, i + 3)),
          ] else ...[
            _source('الأبيات ${isolatedRange(list.first.fromVerse, list.last.toVerse)}', list.first.fromVerse, c),
            for (final r in list) _row(c, r),
          ],
        ],
      ),
    );
  }

  /// Where the poem defines the tab's symbols: opens the reader there.
  Widget _source(String text, int verse, TzColors c) => Semantics(
        button: true,
        child: InkWell(
          key: RumuzScreen.sourceKey,
          onTap: () => _openVerse(verse),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: TzSize.touchTarget),
            child: Row(
              children: [
                Expanded(child: Text(text, style: TzType.caption.copyWith(color: c.ink2))),
                TzIcon('chev', size: 18, color: c.ink3),
              ],
            ),
          ),
        ),
      );

  bool _isFocus(Ramz r) => r.code == widget.focus;

  /// A symbol and who it stands for, side by side.
  Widget _cell(TzColors c, Ramz r, {required bool imam}) => Semantics(
        label: 'رمز ${r.code}: ${r.label}',
        excludeSemantics: true,
        child: Row(
          key: _isFocus(r) ? _focused : null,
          children: [
            SymbolChip(r.code, size: 20, active: _isFocus(r)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(r.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: imam ? TzType.label.copyWith(color: c.ink, fontWeight: FontWeight.w700) : TzType.label.copyWith(color: c.ink2)),
            ),
          ],
        ),
      );

  /// One of the seven readers: his number, his letter, then his two transmitters'.
  /// With large text the transmitters go under him.
  Widget _reader(TzColors c, int number, List<Ramz> three) {
    final large = MediaQuery.textScalerOf(context).scale(TzType.label.fontSize!) > TzType.label.fontSize! * 1.3;
    final imam = _cell(c, three[0], imam: true);
    final first = _cell(c, three[1], imam: false), second = _cell(c, three[2], imam: false);
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.lineSoft))),
      child: Row(
        children: [
          Khatam(ar(number), size: 26),
          const SizedBox(width: 8),
          Expanded(
            child: large
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      imam,
                      const SizedBox(height: 8),
                      Row(children: [Expanded(child: first), const SizedBox(width: 8), Expanded(child: second)]),
                    ],
                  )
                : Row(children: [Expanded(child: imam), Expanded(child: first), Expanded(child: second)]),
          ),
        ],
      ),
    );
  }

  /// A group letter or a code word: who it stands for, and its source verse.
  Widget _row(TzColors c, Ramz r) {
    final members = _members(r);
    final verse = 'البيت ${_verses(r)}';
    return Semantics(
      button: true,
      label: 'رمز ${r.code}: ${r.label}${members == null ? '' : ' ($members)'}، $verse',
      excludeSemantics: true,
      onTap: () => _openVerse(r.fromVerse),
      child: InkWell(
        key: _isFocus(r) ? _focused : null,
        onTap: () => _openVerse(r.fromVerse),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.lineSoft))),
          child: Row(
            children: [
              // The widest word («صحاب») sets the column, so the names line up.
              SizedBox(
                width: _tab == RamzKind.word ? 84 : 48,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SymbolChip(r.code, size: 22, active: _isFocus(r)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(r.label, style: TzType.label.copyWith(color: c.ink, fontWeight: FontWeight.w700)),
                    if (members != null) Text(members, style: TzType.caption.copyWith(color: c.ink2)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(verse, style: TzType.caption.copyWith(color: c.ink3)),
              TzIcon('chev', size: 18, color: c.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

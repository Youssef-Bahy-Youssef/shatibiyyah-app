// lib/ui/reader/verse_rubrics.dart — the reader names and symbols of a verse as
// rubric marks, from the span data (rumuz_spans, ADRs 0015, 0021), and what a
// symbol's tip says. A verse still in review has none.
import '../../data/app_content.dart';
import '../../data/rumuz_repository.dart';
import '../../utils/arabic.dart';
import '../design/components/rubric.dart';

/// The words of [span] in verse [verse].
String spanWords(AppContent content, int verse, RumuzSpan span) {
  final v = content.matn.verse(verse);
  return (span.hemistich == 1 ? v.firstHemistich : v.secondHemistich).substring(span.start, span.end);
}

/// The marks of [verse]: a name whole, a symbol its letter with what it stands for.
List<Rubric> verseRubrics(AppContent content, int verse) => [
      for (final s in content.rumuz.spansOf(verse))
        Rubric.at(s.start, s.end,
            hemistich: s.hemistich,
            isSymbol: !s.isName,
            label: s.isName ? null : 'رمز ${spanWords(content, verse, s)}: ${symbolTitle(content, s)}'),
    ];

/// The span of [verse] that [mark] was made from.
RumuzSpan? spanOf(AppContent content, int verse, Rubric mark) {
  for (final s in content.rumuz.spansOf(verse)) {
    if (s.hemistich == mark.hemistich && s.start == mark.start) return s;
  }
  return null;
}

/// Who a symbol stands for: its name in the list of symbols, or its readers.
String symbolTitle(AppContent content, RumuzSpan span) {
  final ramz = span.symbol == null ? null : content.rumuz.byCode(span.symbol!);
  if (ramz != null) return ramz.label;
  return [for (final id in span.readerIds) ?content.rumuz.reader(id)?.name].join('، ');
}

/// A symbol's kind and the verse of the poem that defines it:
/// «رمز حرفي · من «أبجد»، البيت ٤٥».
String symbolCaption(AppContent content, RumuzSpan span) {
  final ramz = span.symbol == null ? null : content.rumuz.byCode(span.symbol!);
  if (ramz == null) return 'رمز';
  final where = ramz.fromVerse == ramz.toVerse
      ? 'البيت ${ar(ramz.fromVerse)}'
      : 'الأبيات ${isolatedRange(ramz.fromVerse, ramz.toVerse)}';
  return switch (ramz.kind) {
    RamzKind.letter => 'رمز حرفي · من «أبجد»، $where',
    RamzKind.groupLetter => 'رمز جماعة · من «أبجد»، $where',
    RamzKind.word => 'رمز كلمي · $where',
  };
}

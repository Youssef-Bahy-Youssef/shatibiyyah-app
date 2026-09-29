// lib/domain/normalizer.dart — Dart port of shatibiyyah-data's `normalize_matching`.
//
// content.sqlite stores `normalized_text` for verses, commentary segments and
// footnotes, written by the Python pipeline. A search query must be normalized
// the same way or it will miss. The character classes live in
// normalizer_tables.dart, generated from the Python module by
// tool/gen_normalizer.py; test/normalizer_parity_test.dart checks the port
// against the pipeline's own output.
//
// Steps, in the Python order: NFKC (presentation and width forms), drop
// invisible characters, drop tatweel, drop tashkeel and Quranic marks, fold
// hamza seats / yaa / taa marbuta / kaf / waw-hamza, turn brackets and
// punctuation into spaces, collapse whitespace, trim.
import 'normalizer_tables.dart';

export 'normalizer_tables.dart' show kNormalizerVersion;

/// Matching-level normalization: tashkeel-, hamza-seat- and punctuation-blind.
String normalizeMatching(String text) {
  final out = StringBuffer();
  var pendingSpace = false;
  var started = false;

  void emit(int rune) {
    if (kInvisibles.contains(rune) || rune == kTatweel || kMarks.contains(rune)) return;
    final folded = kFolds[rune] ?? rune;
    if (kToSpace.contains(folded) || kWhitespace.contains(folded)) {
      if (started) pendingSpace = true;
      return;
    }
    if (pendingSpace) {
      out.writeCharCode(0x20);
      pendingSpace = false;
    }
    out.writeCharCode(folded);
    started = true;
  }

  for (final rune in text.runes) {
    final expanded = kNfkc[rune];
    if (expanded == null) {
      emit(rune);
    } else {
      expanded.runes.forEach(emit);
    }
  }
  return out.toString();
}

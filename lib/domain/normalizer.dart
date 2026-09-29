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

/// [normalizeMatching] that also says where each output code unit came from:
/// `source[i]` is the UTF-16 offset in [text] of the character that produced
/// `text[i]` (a folded space points at the character that follows it). Used to cut
/// a display snippet around a match found in normalized text.
({String text, List<int> source}) normalizeMatchingMapped(String text) {
  final out = StringBuffer();
  final source = <int>[];
  var pendingSpace = false;
  var started = false;

  void emit(int rune, int at) {
    if (kInvisibles.contains(rune) || rune == kTatweel || kMarks.contains(rune)) return;
    final folded = kFolds[rune] ?? rune;
    if (kToSpace.contains(folded) || kWhitespace.contains(folded)) {
      if (started) pendingSpace = true;
      return;
    }
    if (pendingSpace) {
      out.writeCharCode(0x20);
      source.add(at);
      pendingSpace = false;
    }
    final before = out.length;
    out.writeCharCode(folded);
    for (var i = before; i < out.length; i++) {
      source.add(at);
    }
    started = true;
  }

  var at = 0;
  for (final rune in text.runes) {
    final expanded = kNfkc[rune];
    if (expanded == null) {
      emit(rune, at);
    } else {
      for (final r in expanded.runes) {
        emit(r, at);
      }
    }
    at += rune > 0xFFFF ? 2 : 1;
  }
  return (text: out.toString(), source: source);
}


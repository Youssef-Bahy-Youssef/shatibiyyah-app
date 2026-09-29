// lib/utils/arabic.dart — Arabic-Indic numeral + time helpers.
// ported from app.js: AR(), fmtTime(), normDigits()
import 'dart:math' as math;

const String _arDigits = '٠١٢٣٤٥٦٧٨٩';

/// ported from app.js:
///   const AR = (n) => Number(n).toLocaleString("ar-EG",
///       { useGrouping:false, maximumFractionDigits:2 });
/// Eastern-Arabic digits, no grouping, Arabic decimal separator (U+066B), ≤2 frac digits.
String ar(num n) {
  String s;
  if (n == n.truncateToDouble()) {
    s = n.toInt().toString();
  } else {
    s = n.toStringAsFixed(2);
    // trim trailing zeros / dot (maximumFractionDigits, not minimum)
    s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
  final b = StringBuffer();
  for (final ch in s.split('')) {
    if (ch == '.') {
      b.write('٫'); // U+066B Arabic decimal separator
    } else if (ch == '-') {
      b.write('-');
    } else {
      final d = int.tryParse(ch);
      b.write(d != null ? _arDigits[d] : ch);
    }
  }
  return b.toString();
}

/// A count with its noun agreeing with the number: [one] «بيت واحد», [two] «بيتان»,
/// [plural] for 3–10 «أبيات», [accusative] for 11–99 «بيتًا», [singular] otherwise
/// (100, 101, 102 …).
String _counted(int n, String one, String two, String plural, String accusative, String singular) {
  if (n == 1) return one;
  if (n == 2) return two;
  final r = n % 100;
  if (r >= 3 && r <= 10) return '${ar(n)} $plural';
  if (r >= 11) return '${ar(n)} $accusative';
  return '${ar(n)} $singular';
}

/// «بيت واحد», «بيتان», «٩ أبيات», «١١ بيتًا», «١٠١ بيت».
String versesCount(int n) => _counted(n, 'بيت واحد', 'بيتان', 'أبيات', 'بيتًا', 'بيت');

/// «باب واحد», «بابان», «٩ أبواب», «١١ بابًا».
String chaptersCount(int n) => _counted(n, 'باب واحد', 'بابان', 'أبواب', 'بابًا', 'باب');

/// «بيت واحد محدد», «بيتان محددان», «٩ أبيات محددة», «١١ بيتًا محددًا».
String selectedVersesCount(int n) =>
    _counted(n, 'بيت واحد محدد', 'بيتان محددان', 'أبيات محددة', 'بيتًا محددًا', 'بيت محدد');

/// Wraps a number range so it keeps its order inside Arabic text (FSI … PDI). Next to
/// numbers use «،» as the separator: in Reem Kufi a «·» there reads as the digit «٠».
String isolatedRange(int from, int to) => '\u2068${ar(from)}–${ar(to)}\u2069';

/// ported from app.js: fmtTime(sec)
String fmtTime(num sec) {
  final s0 = math.max(0, sec.isNaN ? 0 : sec.floor());
  final m = s0 ~/ 60;
  final s = s0 % 60;
  return '${ar(m)}:${s < 10 ? '٠${ar(s)}' : ar(s)}';
}

/// ported from app.js: normDigits(str) — fold Arabic-Indic / Persian digits to ASCII.
String normDigits(String str) {
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in str.split('')) {
    final ai = _arDigits.indexOf(ch);
    final pi = persian.indexOf(ch);
    if (ai >= 0) {
      b.write(ai.toString());
    } else if (pi >= 0) {
      b.write(pi.toString());
    } else {
      b.write(ch);
    }
  }
  return b.toString();
}

/// clamp helper mirroring the JS `clamp(v,a,b)` used everywhere.
num clampNum(num v, num a, num b) => math.min(b, math.max(a, v));

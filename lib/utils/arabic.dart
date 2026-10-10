// lib/utils/arabic.dart — Arabic-Indic numeral + time helpers.
// ported from app.js: AR(), fmtTime(), normDigits()
import 'dart:math' as math;

import 'package:flutter/material.dart' show DateUtils;

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

/// The chapter's ordinal, «الباب الأول» … «الباب السابع والسبعون» (1…99); the
/// introduction (0) has none.
String chapterOrdinal(int n) {
  const units = ['', 'الأول', 'الثاني', 'الثالث', 'الرابع', 'الخامس', 'السادس', 'السابع', 'الثامن', 'التاسع'];
  const tens = ['', 'العاشر', 'العشرون', 'الثلاثون', 'الأربعون', 'الخمسون', 'الستون', 'السبعون', 'الثمانون', 'التسعون'];
  if (n < 1 || n > 99) return 'الباب ${ar(n)}';
  final u = n % 10, t = n ~/ 10;
  final unit = u == 1 && n > 10 ? 'الحادي' : units[u];
  final String s;
  if (n < 10) {
    s = units[n];
  } else if (n == 10) {
    s = tens[1];
  } else if (n < 20) {
    s = '$unit عشر';
  } else if (u == 0) {
    s = tens[t];
  } else {
    s = '$unit و${tens[t]}';
  }
  return 'الباب $s';
}

/// Wraps a number range so it keeps its order inside Arabic text (FSI … PDI). Next to
/// numbers use «،» as the separator: in Reem Kufi a «·» there reads as the digit «٠».
String isolatedRange(int from, int to) => '\u2068${ar(from)}–${ar(to)}\u2069';

/// «١٤٥ م.ب» (decimal megabytes, as the store and the prototype count them).
String megabytes(int bytes) => '${ar((bytes / 1e6).round())} م.ب';

/// «٣٫٤ غ.ب».
String gigabytes(int bytes) => '${ar(double.parse((bytes / 1e9).toStringAsFixed(1)))} غ.ب';

/// «٢:٣٠:٣٧» — hours, minutes, seconds (rounded), kept left to right like a clock
/// inside Arabic text (LRI … PDI).
String durationHms(int ms) {
  final s = (ms + 500) ~/ 1000;
  String two(int n) => n < 10 ? '٠${ar(n)}' : ar(n);
  return '\u2066${ar(s ~/ 3600)}:${two(s % 3600 ~/ 60)}:${two(s % 60)}\u2069';
}

/// «دقيقة واحدة», «دقيقتان», «٣ دقائق», «١٢ دقيقة».
String minutesCount(int n) => _counted(n, 'دقيقة واحدة', 'دقيقتان', 'دقائق', 'دقيقة', 'دقيقة');

const List<String> _weekdays = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

/// «اليوم», «أمس», the weekday within the last week, else «١٢/٩» (day/month).
String dayLabel(DateTime at, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final days = today.difference(DateUtils.dateOnly(at)).inDays;
  if (days <= 0) return 'اليوم';
  if (days == 1) return 'أمس';
  if (days < 7) return _weekdays[at.weekday - 1];
  return '\u2066${ar(at.day)}/${ar(at.month)}\u2069';
}

/// «٩:٣٠» (24-hour), left to right like a clock.
String clockTime(DateTime at) {
  final m = at.minute < 10 ? '٠${ar(at.minute)}' : ar(at.minute);
  return '\u2066${ar(at.hour)}:$m\u2069';
}

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

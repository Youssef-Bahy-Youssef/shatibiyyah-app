// Item 3.1 (ADRs 0013, 0019, 0020): lib/ui/design/tokens.g.dart is the one token
// source. It is up to date with the spec (the generator is re-run and diffed when
// the workspace is checked out around the app), and every offered night ink meets
// pageAccent.targets with the same checks as tools/night_page_accent.py.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' show Brightness, ThemeData;
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

/// The generator, where the workspace puts it: the app inside the workspace
/// (`app/`), or the two repositories side by side.
File? _generator() {
  for (final root in ['..', '../shatibiyyah-data']) {
    final f = File('$root/design/redesign/tools/gen_flutter_tokens.py');
    if (f.existsSync()) return f;
  }
  return null;
}

// ── colour science, as in design/redesign/tools/night_page_accent.py ──

List<double> _rgb(Color c) => [c.r, c.g, c.b];
List<double> _mix(List<double> a, List<double> b, double t) => [for (var i = 0; i < 3; i++) a[i] * (1 - t) + b[i] * t];
double _lin(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _lum(List<double> c) {
  double f(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  final v = [for (final x in c) x.clamp(0.0, 1.0)];
  return 0.2126 * f(v[0]) + 0.7152 * f(v[1]) + 0.0722 * f(v[2]);
}

double _ratio(List<double> a, List<double> b) {
  final la = _lum(a), lb = _lum(b);
  return ((math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05) * 100).round() / 100;
}

const _cvd = {
  'protan': [
    [0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998], //
  ],
  'deutan': [
    [0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881], //
  ],
  'tritan': [
    [1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900], //
  ],
};

List<double> _simulate(List<double> c, String kind) {
  final m = _cvd[kind]!;
  final l = [for (final x in c) _lin(x)];
  return [
    for (final row in m)
      () {
        final v = (row[0] * l[0] + row[1] * l[1] + row[2] * l[2]).clamp(0.0, 1.0);
        return v <= 0.0031308 ? v * 12.92 : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
      }(),
  ];
}

List<double> _lab(List<double> c) {
  final l = [for (final x in c) _lin(x)];
  final x = (l[0] * 0.4124 + l[1] * 0.3576 + l[2] * 0.1805) / 0.95047;
  final y = l[0] * 0.2126 + l[1] * 0.7152 + l[2] * 0.0722;
  final z = (l[0] * 0.0193 + l[1] * 0.1192 + l[2] * 0.9505) / 1.08883;
  double f(double t) => t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))];
}

/// CIEDE2000.
double _deltaE(List<double> c1, List<double> c2) {
  double rad(double d) => d * math.pi / 180;
  double deg(double r) => r * 180 / math.pi;
  final [l1, a1, b1] = _lab(c1);
  final [l2, a2, b2] = _lab(c2);
  final cb = (math.sqrt(a1 * a1 + b1 * b1) + math.sqrt(a2 * a2 + b2 * b2)) / 2;
  final g = 0.5 * (1 - math.sqrt(math.pow(cb, 7) / (math.pow(cb, 7) + math.pow(25, 7))));
  final a1p = (1 + g) * a1, a2p = (1 + g) * a2;
  final c1p = math.sqrt(a1p * a1p + b1 * b1), c2p = math.sqrt(a2p * a2p + b2 * b2);
  final h1 = deg(math.atan2(b1, a1p)) % 360, h2 = deg(math.atan2(b2, a2p)) % 360;
  final dL = l2 - l1, dC = c2p - c1p;
  var dh = h2 - h1;
  if (c1p * c2p == 0) {
    dh = 0;
  } else if (dh > 180) {
    dh -= 360;
  } else if (dh < -180) {
    dh += 360;
  }
  final dH = 2 * math.sqrt(c1p * c2p) * math.sin(rad(dh / 2));
  final lb = (l1 + l2) / 2, cbp = (c1p + c2p) / 2;
  final hb = (h1 - h2).abs() <= 180 ? (h1 + h2) / 2 : (h1 + h2 + 360) / 2;
  final t = 1 -
      0.17 * math.cos(rad(hb - 30)) +
      0.24 * math.cos(rad(2 * hb)) +
      0.32 * math.cos(rad(3 * hb + 6)) -
      0.2 * math.cos(rad(4 * hb - 63));
  final sl = 1 + 0.015 * math.pow(lb - 50, 2) / math.sqrt(20 + math.pow(lb - 50, 2));
  final sc = 1 + 0.045 * cbp, sh = 1 + 0.015 * cbp * t;
  final rt = -2 *
      math.sqrt(math.pow(cbp, 7) / (math.pow(cbp, 7) + math.pow(25, 7))) *
      math.sin(rad(60 * math.exp(-math.pow((hb - 275) / 25, 2))));
  return math.sqrt(math.pow(dL / sl, 2) + math.pow(dC / sc, 2) + math.pow(dH / sh, 2) + rt * (dC / sc) * (dH / sh));
}

double _round1(double v) => (v * 10).round() / 10;

void main() {
  test('tokens.g.dart is up to date with tokens.json and v2.css', () async {
    final gen = _generator();
    if (gen == null) {
      markTestSkipped('the workspace (design/redesign/) is not checked out around the app');
      return;
    }
    final run = await Process.run('python3', [gen.path, '--stdout']);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    expect(File('lib/ui/design/tokens.g.dart').readAsStringSync(), run.stdout,
        reason: 'run: python3 design/redesign/tools/gen_flutter_tokens.py');
  });

  test('ThemeData for each theme comes from the tokens: Material follows paper and night', () {
    for (final (tz, brightness) in [(TzTheme.paper, Brightness.light), (TzTheme.dark, Brightness.dark)]) {
      final ThemeData t = tzThemeData(tz);
      final c = tz.colors;
      expect(t.brightness, brightness);
      expect(t.colorScheme.brightness, brightness);
      expect((t.scaffoldBackgroundColor, t.colorScheme.surface, t.colorScheme.onSurface), (c.bg, c.surface, c.ink));
      expect((t.colorScheme.primary, t.colorScheme.onPrimary, t.colorScheme.error), (c.action, c.onAction, c.carmine));
      expect(t.snackBarTheme.backgroundColor, c.snack);
      expect(t.textTheme.bodyMedium!.fontFamily, TzFont.ui);
      expect(t.textTheme.bodyMedium!.fontSize, TzType.body.fontSize);
      expect(t.extension<TzTheme>(), same(tz));
    }
    expect(TzTheme.paper.rubric, TzColors.paper.rubric);
    expect(TzTheme.dark.copyWith(nightInk: TzNightPage.wisteria).rubric, TzNightPage.wisteria.accent);
  });

  test('no colour or font-size literal outside lib/ui/design/', () {
    final literals = {
      'a colour literal': RegExp(r'\bColor(\.fromARGB|\.fromRGBO)?\(\s*[0-9]'),
      'a Material colour': RegExp(r'\bColors\.(?!transparent\b)\w+'),
      'a font-size literal': RegExp(r'\bfontSize:\s*[0-9]'),
    };
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.startsWith('lib/ui/design/')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].split('//').first;
        for (final e in literals.entries) {
          if (e.value.hasMatch(code)) found.add('${f.path}:${i + 1}: ${e.key}: ${lines[i].trim()}');
        }
      }
    }
    expect(found, isEmpty, reason: 'colours and type sizes come from tokens.g.dart');
  });

  test('the legacy palette and helpers are gone', () {
    expect(File('lib/theme.dart').existsSync(), isFalse, reason: 'C, R, kufi(), naskh() and ui() are replaced by the tokens');
    final uses = <String>[];
    final legacy = RegExp(r'''[/']theme\.dart['"]|(?<![\w.])(kufi|naskh)\(|(?<![\w.])C\.\w|\bkFont(Naskh|Kufi|Fallback)\b''');
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (legacy.hasMatch(lines[i].split('//').first)) uses.add('${f.path}:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(uses, isEmpty);
    // The legacy role names survive only as names: each is one token (decision D1, option A).
    final roles = File('lib/ui/design/taysir_colors.dart').readAsStringSync();
    expect(RegExp(r'Color\(\s*0x').hasMatch(roles), isFalse, reason: 'taysir_colors.dart holds no colour values');
  });

  group('every offered night ink meets pageAccent.targets', () {
    final page = _rgb(TzNightPage.pageBg), ink = _rgb(TzNightPage.pageInk), on = _rgb(TzNightPage.onAccent);
    final playingWash = _mix(page, _rgb(TzColors.night.gilt), 0.24);
    final targets = TzNightPage.contrastTargets;

    test('five inks, jade first and the default; the legacy pink is not offered', () {
      expect([for (final i in TzNightPage.inks) i.id], ['jade', 'turquoise', 'lapis', 'wisteria', 'pistachio']);
      expect(TzNightPage.defaultInk, 'jade');
      expect(TzColors.night.rubric, TzNightPage.jade.accent); // the rubric at night is the default ink
      for (final i in TzNightPage.inks) {
        expect(i.matrix, hasLength(20));
      }
    });

    for (final i in TzNightPage.inks) {
      test(i.id, () {
        final a = _rgb(i.accent);
        final measured = {
          'accent/page': _ratio(a, page),
          'onAccent/accent': _ratio(on, a),
          'ink/wash': _ratio(ink, _rgb(i.wash)),
          'accent/playingWash': _ratio(a, playingWash),
          'focusRing/page': _ratio(a, page),
          'disabled/page': _ratio(_rgb(i.disabled), page),
        };
        expect(measured.keys.toSet(), targets.keys.toSet());
        for (final MapEntry(:key, :value) in targets.entries) {
          expect(measured[key], greaterThanOrEqualTo(value), reason: key);
        }
        expect(_round1(_deltaE(a, ink)), greaterThanOrEqualTo(TzNightPage.deltaEFromInk), reason: 'ΔE normal');
        for (final kind in _cvd.keys) {
          expect(_round1(_deltaE(_simulate(a, kind), _simulate(ink, kind))), greaterThanOrEqualTo(TzNightPage.deltaEFromInk),
              reason: 'ΔE $kind');
        }
      });
    }
  });
}

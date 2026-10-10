// Item 3.2 (ADR 0019): IBM Plex Sans Arabic 400–700 (OFL, with its licence) is
// bundled and Reem Kufi is gone; Scheherazade New 400/500/700 stays. The
// prototype's sprite is exported as assets/icons/*.svg (up to date with v2.js
// when the workspace is checked out around the app) and drawn by one TzIcon:
// 24 grid, 1.6 stroke, round caps; transport and active-tab glyphs filled;
// "next verse" points left.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_icon.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

/// The pubspec's font families: family → the weights of its assets that exist.
Map<String, Set<int>> _fonts() {
  final out = <String, Set<int>>{};
  String? family;
  int? weight;
  String? asset;
  void flush() {
    final (f, a) = (family, asset);
    if (f != null && a != null) {
      expect(File(a).existsSync(), isTrue, reason: a);
      out.putIfAbsent(f, () => {}).add(weight ?? 400);
    }
    asset = null;
    weight = null;
  }

  for (final line in File('pubspec.yaml').readAsLinesSync()) {
    final f = RegExp(r'^\s+- family: (\S+)').firstMatch(line);
    final a = RegExp(r'^\s+- asset: (\S+\.(ttf|otf))').firstMatch(line);
    final w = RegExp(r'^\s+weight: (\d+)').firstMatch(line);
    if (f != null) {
      flush();
      family = f.group(1);
    } else if (a != null) {
      flush();
      asset = a.group(1);
    } else if (w != null) {
      weight = int.parse(w.group(1)!);
    }
  }
  flush();
  return out;
}

void main() {
  group('fonts', () {
    test('IBM Plex Sans Arabic 400–700 is bundled under the token family name, with its OFL licence', () {
      expect(_fonts()[TzFont.ui], {400, 500, 600, 700});
      final licence = File('assets/fonts/OFL-IBMPlexSansArabic.txt');
      expect(licence.existsSync(), isTrue);
      expect(licence.readAsStringSync(), contains('SIL Open Font License'));
    });

    test('Reem Kufi is removed; Scheherazade New 400/500/700 stays', () {
      final fonts = _fonts();
      expect(fonts.keys, isNot(contains('ReemKufi')));
      expect(Directory('assets/fonts').listSync().map((f) => f.path), isNot(anyElement(contains('ReemKufi'))));
      expect(fonts[TzFont.text], containsAll({400, 500, 700}));
    });
  });

  group('icons', () {
    test('every sprite glyph is an asset, and nothing else is', () {
      final files = {
        for (final f in Directory('assets/icons').listSync().whereType<File>())
          if (f.path.endsWith('.svg')) f.uri.pathSegments.last.replaceAll('.svg', ''),
      };
      expect(files, kTzIcons.toSet());
      expect(File('pubspec.yaml').readAsStringSync(), contains('    - assets/icons/'));
    });

    test('the assets are up to date with the sprite in v2.js', () async {
      final workspace = ['..', '../shatibiyyah-data'].any((r) => File('$r/design/redesign/v2.js').existsSync());
      if (!workspace) {
        markTestSkipped('the workspace (design/redesign/) is not checked out around the app');
        return;
      }
      final run = await Process.run('python3', ['tool/export_icons.py', '--check']);
      expect(run.exitCode, 0, reason: '${run.stderr}');
    });

    test('one grid, one stroke: 24 × 24, 1.6, round caps and joins', () {
      for (final name in kTzIcons) {
        final svg = File('assets/icons/$name.svg').readAsStringSync();
        expect(svg, startsWith('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
            'stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">'), reason: name);
      }
    });

    test('"next verse" points left and "previous" right (RTL): no mirroring at draw time', () {
      double barX(String name) =>
          double.parse(RegExp(r'<rect x="([\d.]+)"').firstMatch(File('assets/icons/$name.svg').readAsStringSync())!.group(1)!);
      expect(barX('next'), lessThan(12)); // the bar the triangle points at is on the left
      expect(barX('prev'), greaterThan(12));
    });

    test('transport and active-tab glyphs are the filled ones', () {
      expect(kTzFilledIcons, containsAll(['play', 'pause', 'next', 'prev', 'book-f', 'list-f', 'gear-f']));
      expect(kTzIcons, containsAll(kTzFilledIcons));
      expect(filledSvg('<svg a fill="none" stroke="currentColor" stroke-width="1.6"><path/></svg>'),
          '<svg a fill="currentColor" stroke="none" stroke-width="1.6"><path/></svg>');
    });

    Future<void> pump(WidgetTester tester, Widget child, {TzTheme tz = TzTheme.paper}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: tzThemeData(tz),
          home: Directionality(textDirection: TextDirection.rtl, child: Center(child: child)),
        ),
      );
      await tester.pumpAndSettle(); // a theme change animates
    }

    testWidgets('TzIcon: 24 px by default, ink from the theme, filled on request; decorative unless labelled', (tester) async {
      await pump(tester, TzIcon('search'));
      final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(tester.getSize(find.byType(TzIcon)), const Size(24, 24));
      expect((picture.bytesLoader as TzIconLoader).filled, isFalse);
      expect((picture.bytesLoader as TzIconLoader).theme!.currentColor, TzColors.paper.ink);
      expect(find.bySemanticsLabel(RegExp('.')), findsNothing);

      await pump(tester, TzIcon('play', filled: true, size: 28, semanticLabel: 'تشغيل'), tz: TzTheme.dark);
      final play = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect((play.bytesLoader as TzIconLoader).filled, isTrue);
      expect((play.bytesLoader as TzIconLoader).theme!.currentColor, TzColors.night.ink);
      expect(tester.getSize(find.byType(TzIcon)), const Size(28, 28));
      expect(find.bySemanticsLabel('تشغيل'), findsOneWidget);
    });

    testWidgets('TzIcon follows IconTheme colour and size when it has none of its own', (tester) async {
      await pump(tester, IconTheme(data: const IconThemeData(color: Color(0xFF123456), size: 20), child: TzIcon('x')));
      final loader = tester.widget<SvgPicture>(find.byType(SvgPicture)).bytesLoader as TzIconLoader;
      expect(loader.theme!.currentColor, const Color(0xFF123456));
      expect(tester.getSize(find.byType(TzIcon)), const Size(20, 20));
    });

    test('an unknown name fails loudly', () {
      expect(() => TzIcon('nope'), throwsAssertionError);
    });
  });
}

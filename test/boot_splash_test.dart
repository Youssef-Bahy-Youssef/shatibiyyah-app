// The launch splash: at least 1200 ms, a 400 ms fade, the slow-loading line only
// after 2 s, and a tap skips the minimum wait but never the loading. It begins as
// the platform's launch screen leaves off (the logo alone, at the launch
// screen's size, in the middle of the screen) and settles into its own picture.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/taysir_logo.dart';
import 'package:shatibiyyah/ui/shell/boot_splash.dart';

void main() {
  Widget app(bool ready) => MaterialApp(home: BootSplash(ready: ready, child: const Text('reader')));
  final name = find.text('تيسير الشاطبية');

  testWidgets('stays 1200 ms even when loading is instant, then fades out', (tester) async {
    await tester.pumpWidget(app(true));
    expect(name, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(name, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200)); // minimum reached: the fade starts
    await tester.pump(const Duration(milliseconds: 450));
    expect(name, findsNothing);
    expect(find.text('reader'), findsOneWidget);
  });

  testWidgets('the slow-loading line appears only after 2 s', (tester) async {
    await tester.pumpWidget(app(false));
    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.text('يعمل دون اتصال'), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('يعمل دون اتصال'), findsOneWidget);

    await tester.pumpWidget(app(true)); // loading done: fades straight away
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(name, findsNothing);
  });

  testWidgets('a tap skips the minimum wait, not the loading', (tester) async {
    await tester.pumpWidget(app(false));
    await tester.tap(find.byType(BootSplash));
    await tester.pump(const Duration(milliseconds: 500));
    expect(name, findsOneWidget); // still loading

    await tester.pumpWidget(app(true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(name, findsNothing); // well before 1200 ms
  });

  group('lifting', () {
    double target(WidgetTester tester) => tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;
    final lightBars = find.byWidgetPredicate(
        (w) => w is AnnotatedRegion<SystemUiOverlayStyle> && w.value == SystemUiOverlayStyle.light);

    testWidgets('loading that outlasts the minimum: the fade begins a frame after the reader is first built',
        (tester) async {
      await tester.pumpWidget(app(false));
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpWidget(app(true)); // the frame the reader is built in: the heaviest of the launch
      expect(find.text('reader'), findsOneWidget);
      expect(target(tester), 1); // still wholly covered
      await tester.pump();
      expect(target(tester), 0); // now it lifts
    });

    testWidgets('the status bar\'s icons are the splash\'s until it lifts, then the app\'s', (tester) async {
      await tester.pumpWidget(app(true));
      await tester.pump(const Duration(milliseconds: 1100));
      expect(lightBars, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200)); // lifting
      expect(name, findsOneWidget);
      expect(lightBars, findsNothing);
    });
  });

  group('from the launch screen', () {
    final logo = find.byType(TaysirLogo);
    final subtitle = find.text('حِرْزُ الأَمَانِي وَوَجْهُ التَّهَانِي');
    // How much of [text] shows: 0 while the launch screen's picture stands, 1 once the splash has settled.
    double seen(WidgetTester tester, Finder text) =>
        tester.widget<FadeTransition>(find.ancestor(of: text, matching: find.byType(FadeTransition)).first).opacity.value;

    testWidgets('its first frame is the launch screen\'s: the logo alone, at its size, centred', (tester) async {
      await tester.pumpWidget(app(false));
      final screen = tester.getRect(find.byType(BootSplash));
      final first = tester.getRect(logo);
      expect(first.size, const Size.square(kLaunchLogoSize));
      expect(first.center, screen.center);
      expect(seen(tester, name), 0);
    });

    testWidgets('the platform\'s launch screens draw the logo at that size', (tester) async {
      const res = 'android/app/src/main/res';
      // Before Android 12 the launch drawable sizes the logo itself.
      final drawable = File('$res/drawable/launch_background.xml').readAsStringSync();
      final sizes = [
        for (final m in RegExp(r'android:(?:width|height)="([0-9.]+)dp"').allMatches(drawable)) double.parse(m.group(1)!),
      ];
      expect(sizes, [closeTo(kLaunchLogoSize, 0.05), closeTo(kLaunchLogoSize, 0.05)]);
      // From Android 12 the system shows the adaptive icon's foreground, a 108 dp layer, at 288 dp.
      final mark = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(File('$res/mipmap-xxxhdpi/ic_launcher_foreground.png').readAsBytesSync());
        final image = (await codec.getNextFrame()).image;
        final pixels = (await image.toByteData())!;
        var left = image.width, right = -1, top = image.height, bottom = -1;
        for (var y = 0; y < image.height; y++) {
          for (var x = 0; x < image.width; x++) {
            if (pixels.getUint8((y * image.width + x) * 4 + 3) == 0) continue;
            left = math.min(left, x);
            right = math.max(right, x);
            top = math.min(top, y);
            bottom = math.max(bottom, y);
          }
        }
        // The mark fills its own square along its longer side.
        return math.max(right - left + 1, bottom - top + 1) / image.width;
      });
      expect(mark! * 288, closeTo(kLaunchLogoSize, 1));
    });

    testWidgets('it settles in 320 ms: the logo at 176 px over the name, the group centred', (tester) async {
      await tester.pumpWidget(app(false));
      await tester.pump(const Duration(milliseconds: 160));
      final midway = tester.getRect(logo);
      expect(midway.width, inExclusiveRange(kLaunchLogoSize, kSplashLogoSize));
      await tester.pump(const Duration(milliseconds: 160));

      final screen = tester.getRect(find.byType(BootSplash));
      final mark = tester.getRect(logo), title = tester.getRect(name), poem = tester.getRect(subtitle);
      expect(mark.size, const Size.square(kSplashLogoSize));
      expect(seen(tester, name), 1);
      expect(title.top - mark.bottom, 26);
      expect(poem.top - title.bottom, 6);
      // The three stand together in the middle of the screen, as the splash is drawn.
      expect((mark.top + poem.bottom) / 2, moreOrLessEquals(screen.center.dy, epsilon: 0.01));
      expect(mark.center.dx, screen.center.dx);
      expect(title.center.dx, moreOrLessEquals(screen.center.dx, epsilon: 0.01));
    });

    testWidgets('reduced motion: it stands as drawn from its first frame', (tester) async {
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        home: const BootSplash(ready: false, child: Text('reader')),
      ));
      expect(tester.getRect(logo).size, const Size.square(kSplashLogoSize));
      expect(seen(tester, name), 1);
    });
  });
}

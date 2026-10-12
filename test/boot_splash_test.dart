// The launch splash covers loading and nothing more: no minimum time, a 250 ms
// fade. While loading is quick it is the platform's launch screen continued (the
// logo alone, at the launch screen's size, in the middle of the screen); only
// after 2 s of loading does it settle into its own picture, with the progress line.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/taysir_logo.dart';
import 'package:shatibiyyah/ui/shell/boot_splash.dart';

void main() {
  Widget app(bool ready, {Widget child = const Text('reader')}) =>
      MaterialApp(home: BootSplash(ready: ready, child: child));
  final name = find.text('تيسير الشاطبية');
  final logo = find.byType(TaysirLogo);
  final subtitle = find.text('حِرْزُ الأَمَانِي وَوَجْهُ التَّهَانِي');
  // How much of [text] shows: 0 while the launch screen's picture stands, 1 once the splash has settled.
  double seen(WidgetTester tester, Finder text) =>
      tester.widget<FadeTransition>(find.ancestor(of: text, matching: find.byType(FadeTransition)).first).opacity.value;

  testWidgets('no minimum: with loading done it lifts at once and is gone in 250 ms', (tester) async {
    await tester.pumpWidget(app(true)); // the reader is built under it
    expect(logo, findsOneWidget);
    await tester.pump(); // the frame after: it begins to lift
    await tester.pump(const Duration(milliseconds: 240));
    expect(logo, findsOneWidget); // still fading
    await tester.pump(const Duration(milliseconds: 20));
    expect(logo, findsNothing);
    expect(find.text('reader'), findsOneWidget);
  });

  testWidgets('quick loading never shows the name: the launch picture, then the app', (tester) async {
    await tester.pumpWidget(app(false));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.getRect(logo).size, const Size.square(kLaunchLogoSize));
    expect(seen(tester, name), 0);

    await tester.pumpWidget(app(true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125)); // half-way out
    expect(tester.getRect(logo).size, const Size.square(kLaunchLogoSize));
    expect(seen(tester, name), 0);
    await tester.pump(const Duration(milliseconds: 135));
    expect(logo, findsNothing);
  });

  testWidgets('loading longer than 2 s: it settles into its own picture, with the progress line', (tester) async {
    await tester.pumpWidget(app(false));
    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.text('يعمل دون اتصال'), findsNothing);
    expect(seen(tester, name), 0);
    await tester.pump(const Duration(milliseconds: 200)); // 2 s have passed: it begins to settle
    expect(find.text('يعمل دون اتصال'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 160));
    expect(tester.getRect(logo).width, inExclusiveRange(kLaunchLogoSize, kSplashLogoSize));
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

    await tester.pumpWidget(app(true)); // loading done: the line goes, and it lifts
    expect(find.text('يعمل دون اتصال'), findsNothing);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    expect(name, findsNothing);
  });

  testWidgets('touches do not reach what it covers until it lifts', (tester) async {
    var taps = 0;
    final under = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => taps++,
      child: const SizedBox.expand(),
    );
    await tester.pumpWidget(app(false, child: under));
    await tester.tapAt(const Offset(100, 100));
    expect(taps, 0);

    await tester.pumpWidget(app(true, child: under));
    await tester.pump(); // lifting: the app takes touches while the splash fades
    await tester.tapAt(const Offset(100, 100));
    expect(taps, 1);
    await tester.pump(const Duration(milliseconds: 300));
  });

  group('lifting', () {
    double target(WidgetTester tester) => tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;
    final lightBars = find.byWidgetPredicate(
        (w) => w is AnnotatedRegion<SystemUiOverlayStyle> && w.value == SystemUiOverlayStyle.light);

    testWidgets('the fade begins a frame after the reader is first built', (tester) async {
      await tester.pumpWidget(app(false));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(app(true)); // the frame the reader is built in: the heaviest of the launch
      expect(find.text('reader'), findsOneWidget);
      expect(target(tester), 1); // still wholly covered
      await tester.pump();
      expect(target(tester), 0); // now it lifts
    });

    testWidgets('the status bar\'s icons are the splash\'s until it lifts, then the app\'s', (tester) async {
      await tester.pumpWidget(app(false));
      expect(lightBars, findsOneWidget);
      await tester.pumpWidget(app(true));
      expect(lightBars, findsOneWidget);
      await tester.pump(); // lifting
      expect(logo, findsOneWidget);
      expect(lightBars, findsNothing);
    });
  });

  group('from the launch screen', () {
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

    testWidgets('reduced motion: after 2 s it stands as drawn at once', (tester) async {
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        home: const BootSplash(ready: false, child: Text('reader')),
      ));
      expect(tester.getRect(logo).size, const Size.square(kLaunchLogoSize));
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump();
      expect(tester.getRect(logo).size, const Size.square(kSplashLogoSize));
      expect(seen(tester, name), 1);
    });
  });
}

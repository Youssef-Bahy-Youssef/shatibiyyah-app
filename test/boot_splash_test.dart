// The launch splash: at least 1200 ms, a 400 ms fade, the slow-loading line only
// after 2 s, and a tap skips the minimum wait but never the loading. It begins as
// the platform's launch screen leaves off (the logo alone, 144 px, in the middle
// of the screen) and settles into its own picture.
import 'package:flutter/material.dart';
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

  group('from the launch screen', () {
    final logo = find.byType(TaysirLogo);
    final subtitle = find.text('حِرْزُ الأَمَانِي وَوَجْهُ التَّهَانِي');
    // How much of [text] shows: 0 while the launch screen's picture stands, 1 once the splash has settled.
    double seen(WidgetTester tester, Finder text) =>
        tester.widget<FadeTransition>(find.ancestor(of: text, matching: find.byType(FadeTransition)).first).opacity.value;

    testWidgets('its first frame is the launch screen\'s: the logo alone, 144 px, centred', (tester) async {
      await tester.pumpWidget(app(false));
      final screen = tester.getRect(find.byType(BootSplash));
      final first = tester.getRect(logo);
      expect(first.size, const Size.square(kLaunchLogoSize));
      expect(first.center, screen.center);
      expect(seen(tester, name), 0);
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

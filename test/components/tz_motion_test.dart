// Motion (ADR 0037): a tap answers the finger, what leaves fades, pushed screens
// move with the reading, and all of it is instant under reduced motion.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/tz_motion.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import 'harness.dart';

/// The press tint drawn over [finder]'s pressable, or null when there is none.
CustomPaint _tint(WidgetTester tester, Finder finder) => tester.widget<CustomPaint>(
    find.descendant(of: find.ancestor(of: finder, matching: find.byType(TzPressable)), matching: find.byType(CustomPaint)).first);

double _scale(WidgetTester tester, Finder finder) => tester
    .widget<Transform>(find.descendant(of: find.ancestor(of: finder, matching: find.byType(TzPressable)), matching: find.byType(Transform)).first)
    .transform
    .storage[0];

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;
  @override
  Widget build(BuildContext context) => Text('n=$n');
}

void main() {
  group('TzPressable', () {
    testWidgets('held: a tint comes over it and a compact control settles; released, both go', (tester) async {
      var taps = 0;
      await pumpTz(tester, TzPressable(sink: true, onTap: () => taps++, child: const SizedBox(width: 120, height: 48, child: Text('زر'))));
      expect(_tint(tester, find.text('زر')).foregroundPainter, isNull);
      expect(_scale(tester, find.text('زر')), 1);

      final press = await tester.startGesture(tester.getCenter(find.text('زر')));
      await tester.pump(const Duration(milliseconds: 200)); // past the tap's own wait
      await tester.pump(TzMotion.short);
      expect(_tint(tester, find.text('زر')).foregroundPainter, isNotNull);
      expect(_scale(tester, find.text('زر')), closeTo(TzPressable.sinkScale, 0.001));

      await press.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_scale(tester, find.text('زر')), inExclusiveRange(TzPressable.sinkScale, 1)); // on its way back
      await tester.pumpAndSettle();
      expect(_tint(tester, find.text('زر')).foregroundPainter, isNull);
      expect(_scale(tester, find.text('زر')), 1);
      expect(taps, 1);
    });

    testWidgets('a quick tap still shows the press in full', (tester) async {
      await pumpTz(tester, TzPressable(sink: true, onTap: () {}, child: const SizedBox(width: 120, height: 48, child: Text('زر'))));
      await tester.tap(find.text('زر'));
      await tester.pump();
      var deepest = 1.0;
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        deepest = _scale(tester, find.text('زر')) < deepest ? _scale(tester, find.text('زر')) : deepest;
      }
      expect(deepest, closeTo(TzPressable.sinkScale, 0.002));
      await tester.pumpAndSettle();
      expect(_scale(tester, find.text('زر')), 1);
    });

    testWidgets('what it holds keeps its state through a press', (tester) async {
      await pumpTz(tester, TzPressable(onTap: () {}, child: const SizedBox(width: 120, height: 48, child: _Counter())));
      tester.state<_CounterState>(find.byType(_Counter)).n = 7;
      await tester.tap(find.byType(_Counter));
      await tester.pumpAndSettle();
      expect(tester.state<_CounterState>(find.byType(_Counter)).n, 7);
    });

    testWidgets('reduced motion: the press is shown and gone at once', (tester) async {
      await pumpTz(tester, TzPressable(sink: true, onTap: () {}, child: const SizedBox(width: 120, height: 48, child: Text('زر'))),
          reducedMotion: true);
      await tester.tap(find.text('زر'));
      await expectInstant(tester);
      expect(_scale(tester, find.text('زر')), 1);
    });
  });

  group('TzPresence', () {
    Widget host(bool shown, {Object? id, VoidCallback? onUnder}) => SizedBox(
          width: 200,
          height: 100,
          child: Stack(children: [
            Positioned.fill(child: GestureDetector(onTap: onUnder, child: const ColoredBox(color: Color(0xFF000000)))),
            TzPresence(id: id, child: shown ? const SizedBox(width: 200, height: 100, child: _Counter()) : null),
          ]),
        );

    double opacity(WidgetTester tester) =>
        tester.widget<Opacity>(find.ancestor(of: find.byType(_Counter), matching: find.byType(Opacity)).first).opacity;

    testWidgets('a child that goes fades out in 160 ms, and taps reach what is under it meanwhile', (tester) async {
      var under = 0;
      final shown = ValueNotifier(true);
      await pumpTz(tester, ValueListenableBuilder(valueListenable: shown, builder: (_, s, _) => host(s, onUnder: () => under++)));
      expect(opacity(tester), 1);

      shown.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(_Counter), findsOneWidget);
      expect(opacity(tester), inExclusiveRange(0, 1));
      await tester.tapAt(tester.getCenter(find.byType(_Counter)));
      expect(under, 1);

      await tester.pump(TzPresence.exitDuration);
      expect(find.byType(_Counter), findsNothing);
    });

    testWidgets('the same one back before it has gone is taken back where it is, state and all', (tester) async {
      final shown = ValueNotifier(true);
      await pumpTz(tester, ValueListenableBuilder(valueListenable: shown, builder: (_, s, _) => host(s)));
      tester.state<_CounterState>(find.byType(_Counter)).n = 3;
      shown.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      shown.value = true;
      await tester.pumpAndSettle();
      expect(opacity(tester), 1);
      expect(tester.state<_CounterState>(find.byType(_Counter)).n, 3);
    });

    testWidgets('reduced motion: gone at once', (tester) async {
      final shown = ValueNotifier(true);
      await pumpTz(tester, ValueListenableBuilder(valueListenable: shown, builder: (_, s, _) => host(s)), reducedMotion: true);
      shown.value = false;
      await tester.pump();
      await tester.pump();
      expect(find.byType(_Counter), findsNothing);
    });
  });

  testWidgets('a pushed screen comes in from the left in Arabic and the one below moves right (shared axis)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      theme: tzThemeData(TzTheme.paper),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const Scaffold(body: Center(child: Text('الأولى'))),
    ));
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Center(child: Text('الثانية')))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final centre = tester.getCenter(find.text('الثانية')).dx;
    expect(centre, lessThan(195)); // still left of where it will rest
    expect(tester.getCenter(find.text('الأولى')).dx, greaterThan(195)); // moving right
    await tester.pump(TzPageTransitionsBuilder().transitionDuration);
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('الثانية')).dx, closeTo(195, 0.5));
  });
}

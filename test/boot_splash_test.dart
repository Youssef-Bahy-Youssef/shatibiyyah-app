// The launch splash: at least 1200 ms, a 400 ms fade, the slow-loading line only
// after 2 s, and a tap skips the minimum wait but never the loading.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    await tester.tap(name);
    await tester.pump(const Duration(milliseconds: 500));
    expect(name, findsOneWidget); // still loading

    await tester.pumpWidget(app(true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(name, findsNothing); // well before 1200 ms
  });
}

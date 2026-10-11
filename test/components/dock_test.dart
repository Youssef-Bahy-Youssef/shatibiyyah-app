// Dock (item 3.3, ADR 0019; v2.js dock()/npRow(), v2.css .dock): the binding.
// A 62 px now-playing row in one of four states (playing, none, downloading,
// failed) over the four tabs (54 px); the active tab is filled and marked with a
// gilt lozenge. Cover fill, 26 px radius, the dock shadow. 44 px buttons get a
// 48 px target without moving. Playing, the row ends in previous, play, next.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/components/dock.dart';
import 'package:shatibiyyah/ui/design/components/khatam.dart';
import 'package:shatibiyyah/ui/design/components/ornament.dart';
import 'package:shatibiyyah/ui/design/tokens.g.dart';
import 'package:shatibiyyah/ui/design/tz_icon.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import 'harness.dart';

Widget dock(NowPlaying? np, {DockTab current = DockTab.matn, ValueChanged<DockTab>? onTab}) =>
    SizedBox(width: 370, child: Dock(nowPlaying: np, current: current, onTab: onTab ?? (_) {}));

void main() {
  testWidgets('the binding: cover, 26 px radius, dock shadow; row 62 + tabs 54', (tester) async {
    await pumpTz(tester, dock(NpNone(subtitle: 'محمد بن عتيق · ١٤٥ م.ب · مرة واحدة', onDownload: () {})));
    final d = tester.widget<Container>(find.byKey(Dock.bindingKey)).decoration! as BoxDecoration;
    expect((d.color, d.borderRadius, d.boxShadow), (TzColors.paper.cover, BorderRadius.circular(TzRadius.dock), TzColors.paper.dock));
    expect(tester.getSize(find.byKey(Dock.rowKey)).height, 62);
    expect(tester.getSize(find.byKey(Dock.tabsKey)).height, 54);
    await expectAccessible(tester);
  });

  testWidgets('tabs: four, the active one filled in onCover with the lozenge; a tap selects; tab semantics', (tester) async {
    DockTab? tapped;
    await pumpTz(tester, dock(null, current: DockTab.saved, onTab: (t) => tapped = t), tz: TzTheme.dark);
    expect([for (final t in DockTab.values) t.label], ['المتن', 'الفهرس', 'المحفوظ', 'الإعدادات']);
    // RTL: المتن at the start (right).
    expect(tester.getCenter(find.text('المتن')).dx, greaterThan(tester.getCenter(find.text('الإعدادات')).dx));
    final active = tester.widget<Text>(find.text('المحفوظ')).style!;
    expect((active.color, active.fontWeight, active.fontSize), (TzColors.night.onCover, FontWeight.w600, 11.5));
    final idle = tester.widget<Text>(find.text('الفهرس')).style!;
    expect((idle.color, idle.fontWeight), (TzColors.night.coverMute, FontWeight.w500));
    final icons = tester.widgetList<TzIcon>(find.byType(TzIcon)).toList();
    expect([for (final i in icons) (i.name, i.filled)], [('book', false), ('list', false), ('bookmark', true), ('gear', false)]);
    final loz = tester.widget<Lozenge>(find.byType(Lozenge));
    expect((loz.size, loz.color), (5.0, TzColors.night.giltOnCover));
    expect(tester.getCenter(find.byType(Lozenge)).dx, closeTo(tester.getCenter(find.text('المحفوظ')).dx, 0.5));
    expect(find.byKey(Dock.rowKey), findsNothing); // no now-playing row: tabs alone
    await tester.tap(find.text('الفهرس'));
    expect(tapped, DockTab.contents);
    expect(tester.getSemantics(find.text('المحفوظ')), matchesSemantics(label: 'المحفوظ', isButton: true, hasSelectedState: true, isSelected: true, hasTapAction: true, hasFocusAction: true, isFocusable: true));
    await expectAccessible(tester);
  });

  testWidgets('playing: verse khatam, «البيت ٢٢٩ · ٤ من ٩», previous, pause and next; the gilt bar from the start', (tester) async {
    var previouses = 0, toggles = 0, nexts = 0;
    await pumpTz(
      tester,
      dock(NpPlaying(
        verse: '٢٢٩',
        position: '٤ من ٩',
        subtitle: 'محمد بن عتيق · ١٫٢٥× · تكرار ٢/٣',
        playing: true,
        progress: 0.39,
        onPrevious: () => previouses++,
        onToggle: () => toggles++,
        onNext: () => nexts++,
      )),
    );
    expect(tester.widget<Khatam>(find.byType(Khatam)).label, '٢٢٩');
    expect(tester.widget<Khatam>(find.byType(Khatam)).onCover, isTrue);
    expect(find.textContaining('البيت ٢٢٩', findRichText: true), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('البيت السابق'));
    expect((previouses, toggles, nexts), (1, 0, 0));
    await tester.tap(find.bySemanticsLabel('إيقاف مؤقت'));
    expect((previouses, toggles, nexts), (1, 1, 0));
    await tester.tap(find.bySemanticsLabel('البيت التالي'));
    expect((previouses, toggles, nexts), (1, 1, 1));
    final row = tester.getRect(find.byKey(Dock.rowKey));
    final bar = tester.getRect(find.byKey(Dock.barFillKey));
    expect(bar.right, closeTo(row.right - 16, 0.01)); // RTL: fills from the start
    expect(bar.width, closeTo((row.width - 32) * 0.39, 0.5));
    // The transport, in the player's order (RTL: previous at the start side, next at the end):
    // 44 px drawings 4 px apart, the last 8 px from the end, each in a 48 px target that
    // touches the next one. The play button is a 44 px onCover disc.
    final previous = tester.getRect(find.bySemanticsLabel('البيت السابق'));
    final target = tester.getRect(find.bySemanticsLabel('إيقاف مؤقت'));
    final next = tester.getRect(find.bySemanticsLabel('البيت التالي'));
    final disc = tester.getRect(find.byKey(Dock.playDiscKey));
    expect([previous.size, target.size, next.size], everyElement(const Size(48, 48)));
    expect((next.right, target.right), (target.left, previous.left));
    expect(next.left - row.left, closeTo(8 - 2, 0.01));
    expect(disc.size, const Size(44, 44));
    expect(disc.center, target.center);
    expect(disc.left - row.left, closeTo(8 + 44 + 4, 0.01));
    final glyphs = [for (final i in tester.widgetList<TzIcon>(find.descendant(of: find.byKey(Dock.rowKey), matching: find.byType(TzIcon)))) i.name];
    expect(glyphs, ['prev', 'pause', 'next']);
    // The design's own subtitle still fits beside the three buttons on a 390 px phone.
    expect(tester.renderObject<RenderParagraph>(find.text('محمد بن عتيق · ١٫٢٥× · تكرار ٢/٣')).didExceedMaxLines, isFalse);
    await expectAccessible(tester);
  });

  testWidgets('playing on a narrow phone: the text gives way, the three buttons keep their size', (tester) async {
    await pumpTz(
      tester,
      SizedBox(
        width: 300,
        child: Dock(
          nowPlaying: NpPlaying(
            verse: '١١٧٣',
            position: '١٢ من ٤٥',
            subtitle: 'محمد بن عتيق · ١٫٢٥× · تكرار ٢/٣',
            playing: false,
            progress: 0.26,
            onPrevious: () {},
            onToggle: () {},
            onNext: () {},
          ),
          current: DockTab.matn,
          onTab: (_) {},
        ),
      ),
      width: 320,
    );
    expect(tester.takeException(), isNull);
    for (final label in ['البيت السابق', 'تشغيل', 'البيت التالي']) {
      expect(tester.getSize(find.bySemanticsLabel(label)), const Size(48, 48), reason: label);
    }
    expect(tester.renderObject<RenderParagraph>(find.textContaining('البيت ١١٧٣', findRichText: true)).didExceedMaxLines, isTrue);
    await expectAccessible(tester);
  });

  testWidgets('playing: when the second line does not fit, the reciter gives way and the settings stay', (tester) async {
    const name = 'محمد بن عتيق الصنوي';
    Future<void> row(String settings, {double width = 370}) => pumpTz(
          tester,
          SizedBox(
            width: width,
            child: Dock(
              nowPlaying: NpPlaying(
                verse: '٢٢٦',
                position: '١ من ٩',
                subtitle: '$name · $settings',
                compactSubtitle: settings,
                playing: true,
                progress: 0.1,
                onPrevious: () {},
                onToggle: () {},
                onNext: () {},
              ),
              current: DockTab.matn,
              onTab: (_) {},
            ),
          ),
        );
    bool cut(String text) =>
        tester.renderObject<RenderParagraph>(find.descendant(of: find.text(text), matching: find.byType(RichText))).didExceedMaxLines;

    // 138 px in a 150 px column: the whole line.
    await row('١٫٢٥×');
    expect(cut('$name · ١٫٢٥×'), isFalse);
    // 151 and 186 px: the settings alone, whole, and the name is still read out. At «١/٣»
    // the whole line is 148 px, but it is measured at its widest digits, so the line keeps
    // one form while the count ticks.
    for (final settings in ['تكرار ٢/٣', 'تكرار ١/٣', 'تكرار ٣/٣', '١٫٢٥× · تكرار ٢/٣']) {
      await row(settings);
      expect(find.text('$name · $settings'), findsNothing, reason: settings);
      expect(cut(settings), isFalse, reason: settings);
      expect(tester.getSemantics(find.text(settings)).label, contains('$name · $settings'));
    }
    // Wider (a 412 dp phone): room for all of it again.
    await row('تكرار ٢/٣', width: 392);
    expect(cut('$name · تكرار ٢/٣'), isFalse);
    await expectAccessible(tester);
  });

  testWidgets('none, downloading and failed', (tester) async {
    var downloads = 0, retries = 0, pauses = 0;
    await pumpTz(tester, dock(NpNone(subtitle: 'محمد بن عتيق · ١٤٥ م.ب', onDownload: () => downloads++)));
    expect(find.text('استمع إلى المتن'), findsOneWidget);
    await tester.tap(find.text('تنزيل'));
    expect(tester.widget<Khatam>(find.byType(Khatam)).label, '');

    await pumpTz(tester, dock(NpDownloading(percent: '٤٢٪', progress: 0.42, subtitle: '٦١ من ١٤٥ م.ب', onPause: () => pauses++)));
    expect(find.text('جارٍ تنزيل التلاوة'), findsOneWidget);
    expect(tester.widget<Khatam>(find.byType(Khatam)).progress, 0.42);
    await tester.tap(find.bySemanticsLabel('إيقاف مؤقت'));

    await pumpTz(tester, dock(NpFailed(subtitle: 'انقطع الاتصال · سيُستأنف من ٤٢٪', onRetry: () => retries++)), tz: TzTheme.dark);
    expect(tester.widget<Text>(find.text('تعذّر التنزيل')).style!.color, TzColors.night.errOnCover);
    expect(tester.widget<Khatam>(find.byType(Khatam)).error, isTrue);
    await tester.tap(find.text('إعادة'));
    expect((downloads, pauses, retries), (1, 1, 1));
    await expectAccessible(tester);
  });

  testWidgets('the progress bar moves over 320 ms; instantly under reduced motion', (tester) async {
    NpPlaying at(double p) => NpPlaying(verse: '٢٢٩', position: '٤ من ٩', subtitle: '', playing: true, progress: p, onPrevious: () {}, onToggle: () {}, onNext: () {});
    await pumpTz(tester, dock(at(0.2)));
    await pumpTz(tester, dock(at(0.6)), settle: false);
    await tester.pump(const Duration(milliseconds: 100));
    final w = tester.getSize(find.byKey(Dock.barFillKey)).width;
    expect(w, inExclusiveRange(338 * 0.2, 338 * 0.6));
    await tester.pumpAndSettle();
    await pumpTz(tester, dock(at(0.2)), reducedMotion: true);
    await pumpTz(tester, dock(at(0.6)), reducedMotion: true, settle: false);
    await expectInstant(tester);
    expect(tester.getSize(find.byKey(Dock.barFillKey)).width, closeTo(338 * 0.6, 0.5));
  });
}

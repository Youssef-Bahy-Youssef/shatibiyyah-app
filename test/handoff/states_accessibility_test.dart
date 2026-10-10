// Item 3.12 (text scaling, targets): every state of the handoff, as the app
// reaches it, has labelled tap targets of 48 × 48 or more and fits when the
// system text is twice its size.
//
// One exception, as in accessibility_test.dart: on the scanned page each verse
// is its manuscript line, about 25 dp tall and packed with the next. Text mode
// is the full-size way to read verse by verse. Only those lines are exempt:
// everything drawn over the page is still measured.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/services/download_manager.dart';
import 'package:shatibiyyah/ui/design/components/dock.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/shell/app_shell.dart';

import '../../test_goldens/golden_fonts.dart';
import 'fixtures.dart';
import 'states.dart';

/// Tap targets of 48 × 48 or more, but for the verse lines of the scanned page.
class _TargetsButPageLines extends AccessibilityGuideline {
  const _TargetsButPageLines();

  static final _pageLine = RegExp(r'^البيت [٠-٩]+: ');
  static const double _min = 48;

  @override
  String get description => 'Tap targets are 48 × 48 or more (the scanned page\'s verse lines apart)';

  @override
  FutureOr<Evaluation> evaluate(WidgetTester tester) {
    var result = const Evaluation.pass();
    final view = tester.binding.renderViews.first;
    final screen = Offset.zero & view.size;
    void visit(SemanticsNode node) {
      node.visitChildren((child) {
        visit(child);
        return true;
      });
      if (node.isMergedIntoParent) return;
      final data = node.getSemanticsData();
      if (!data.hasAction(SemanticsAction.tap) && !data.hasAction(SemanticsAction.longPress)) return;
      if (data.flagsCollection.isLink || data.flagsCollection.isHidden) return;
      if (_pageLine.hasMatch(data.label)) return;
      var box = node.rect;
      for (SemanticsNode? n = node; n != null; n = n.parent) {
        if (n.transform case final m?) box = MatrixUtils.transformRect(m, box);
        // Cut by its scrollable or by the screen: it may be partly scrolled away.
        final clip = n.parent?.rect;
        if (n.parent != null && n.parent!.getSemanticsData().flagsCollection.hasImplicitScrolling && clip != null) {
          if (box.top <= clip.top + 0.5 || box.bottom >= clip.bottom - 0.5 || box.left <= clip.left + 0.5 || box.right >= clip.right - 0.5) {
            return;
          }
        }
      }
      if (box.left <= screen.left || box.top <= screen.top || box.right >= screen.right || box.bottom >= screen.bottom) return;
      if (box.width < _min - 0.01 || box.height < _min - 0.01) {
        result += Evaluation.fail('«${data.label}» ${data.tooltip}: ${box.width.toStringAsFixed(1)} × ${box.height.toStringAsFixed(1)} at ${box.topLeft}\n');
      }
    }

    visit(view.owner!.semanticsOwner!.rootSemanticsNode!);
    return result;
  }
}

void main() {
  final data = HandoffContent();
  setUpAll(() async {
    await loadGoldenFonts();
    await data.open();
  });
  tearDownAll(data.close);

  Future<ReaderController> show(WidgetTester tester, HandoffState state, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    addTearDown(tester.view.reset);
    final total = data.content.recordings.defaultRecording.localBytes;
    final r = await data.reader(tester,
        audio: state.audio,
        library: state.tab == DockTab.settings || state.audio,
        download: switch (state.download) {
          null => null,
          final phase => DownloadProgress(
              phase, (total * 0.42).ceil(), total, phase == DownloadPhase.failed ? DownloadError.network : null),
        });
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: tzThemeData(TzTheme.paper),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true, textScaler: TextScaler.linear(textScale)),
        child: Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
      home: AppShell(reader: r, initialTab: state.tab),
    ));
    await state.setup(tester, r, data);
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    return r;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  for (final MapEntry(key: name, value: state) in handoffStates.entries) {
    testWidgets('$name: labelled tap targets of 48 × 48 or more', (tester) async {
      final handle = tester.ensureSemantics();
      await show(tester, state);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(const _TargetsButPageLines()));
      await unmount(tester);
      handle.dispose();
    });

    testWidgets('$name: fits at 200 % text', (tester) async {
      // What overflowed, with the widget that did: the exception alone does not say.
      final seen = <String>[];
      final report = FlutterError.onError;
      FlutterError.onError = (details) {
        final all = details.toString();
        seen.add(all.length > 1400 ? all.substring(0, 1400) : all);
        report?.call(details);
      };
      Object? error;
      try {
        await show(tester, state, textScale: 2);
      } on Object catch (e) {
        error = e; // a state's own steps may not find their way at this size: say which
      } finally {
        FlutterError.onError = report;
      }
      error ??= tester.takeException();
      expect(error, isNull, reason: seen.isEmpty ? '$error' : seen.join('\n'));
      await unmount(tester);
    });
  }
}

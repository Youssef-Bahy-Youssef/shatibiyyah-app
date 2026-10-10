// The design handoff as test data (design/redesign/handoff/, plan Phase 3): the
// measured spec of every screen and state, read from the workspace around the
// app. A conformance test pumps the real screen on the prototype's phone
// (390×844 dp, a 44 dp status bar, a 34 dp home indicator) and compares where
// its widgets are with where the spec says they are. Chromium and Flutter shape
// Arabic text a little differently, so text is compared by its line box (its
// start edge, top and height), not its ink.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

import '../../test_goldens/golden_fonts.dart';

/// The prototype's phone.
const Size kHandoffScreen = Size(390, 844);
const FakeViewPadding kHandoffPadding = FakeViewPadding(top: 44, bottom: 34);

class SpecNode {
  final Map<String, dynamic> json;
  const SpecNode(this.json);

  int get id => json['id'] as int;
  Rect get rect => Rect.fromLTWH(
      (json['x'] as num).toDouble(), (json['y'] as num).toDouble(), (json['w'] as num).toDouble(), (json['h'] as num).toDouble());
  String? get text => json['text'] as String?;
  String get cls => (json['class'] as String?) ?? '';
  String? get component => json['component'] as String?;

  /// The token names of a colour property, e.g. `{'ink', 'snack'}` for `rgb(…) = --ink / --snack`.
  Set<String> tokens(String property) {
    final v = json[property] as String?;
    if (v == null || !v.contains('= ')) return const {};
    return {for (final t in v.split('= ').last.split('/')) t.trim().replaceFirst('--', '')};
  }

  @override
  String toString() => '[$id] ${json['tag']}.$cls';
}

class HandoffSpec {
  final String name;
  final List<SpecNode> nodes;
  const HandoffSpec(this.name, this.nodes);

  /// The spec of `<screen>-<state>-<theme>`, or null when the workspace is not
  /// checked out around the app.
  static HandoffSpec? load(String name) {
    for (final root in ['..', '../shatibiyyah-data']) {
      final f = File('$root/design/redesign/handoff/specs/$name.json');
      if (!f.existsSync()) continue;
      final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return HandoffSpec(name, [for (final n in json['nodes'] as List) SpecNode(n as Map<String, dynamic>)]);
    }
    return null;
  }

  SpecNode id(int id) => nodes.firstWhere((n) => n.id == id);

  /// The one node whose text is exactly [text] (and whose class contains [cls]).
  SpecNode text(String text, {String cls = ''}) =>
      nodes.singleWhere((n) => n.text == text && n.cls.contains(cls), orElse: () => throw StateError('$name: no single node «$text»'));

  /// The first node of [component] (the redline's widget name).
  SpecNode component(String component) => nodes.firstWhere((n) => n.component == component);

  /// The first node whose class is exactly [cls].
  SpecNode cls(String cls) => nodes.firstWhere((n) => n.cls == cls);

  List<SpecNode> childrenOf(SpecNode parent) => [for (final n in nodes) if (n.json['parent'] == parent.id) n];
}

/// Collects every difference between the screen and its spec, then fails with all of them.
class Conformance {
  final HandoffSpec spec;
  final List<String> _diffs = [];
  Conformance(this.spec);

  static String _r(Rect r) => '(${r.left.toStringAsFixed(1)}, ${r.top.toStringAsFixed(1)}) ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)}';

  /// The whole box, each edge within [tol] dp.
  void box(String what, Rect actual, Rect expected, {double tol = 1}) {
    final off = [actual.left - expected.left, actual.top - expected.top, actual.right - expected.right, actual.bottom - expected.bottom];
    if (off.any((d) => d.abs() > tol)) _diffs.add('$what: is ${_r(actual)}, spec ${_r(expected)}');
  }

  /// A line of right-to-left text: its start (right) edge, its top and its height.
  void line(String what, Rect actual, Rect expected, {double tol = 1}) {
    final off = [actual.right - expected.right, actual.top - expected.top, actual.height - expected.height];
    if (off.any((d) => d.abs() > tol)) {
      _diffs.add('$what: right ${actual.right.toStringAsFixed(1)} top ${actual.top.toStringAsFixed(1)} h ${actual.height.toStringAsFixed(1)}, '
          'spec right ${expected.right.toStringAsFixed(1)} top ${expected.top.toStringAsFixed(1)} h ${expected.height.toStringAsFixed(1)}');
    }
  }

  /// Something drawn smaller than its tap target: only where its centre is.
  void centre(String what, Rect actual, Rect expected, {double tol = 1}) {
    final d = actual.center - expected.center;
    if (d.dx.abs() > tol || d.dy.abs() > tol) {
      _diffs.add('$what: centre (${actual.center.dx.toStringAsFixed(1)}, ${actual.center.dy.toStringAsFixed(1)}), '
          'spec (${expected.center.dx.toStringAsFixed(1)}, ${expected.center.dy.toStringAsFixed(1)})');
    }
  }

  void same(String what, Object? actual, Object? expected) {
    if (actual != expected) _diffs.add('$what: is $actual, spec $expected');
  }

  void done() => expect(_diffs, isEmpty, reason: '${spec.name}:\n  ${_diffs.join('\n  ')}');
}

bool _fonts = false;

/// Pumps [home] on the prototype's phone, in [tz], with the app's real fonts and
/// reduced motion (the handoff images are end states).
Future<void> pumpPhone(WidgetTester tester, Widget home, {TzTheme tz = TzTheme.paper}) async {
  if (!_fonts) {
    await tester.runAsync(loadGoldenFonts);
    _fonts = true;
  }
  tester.view.physicalSize = kHandoffScreen;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = kHandoffPadding;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: tzThemeData(tz),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: Directionality(textDirection: TextDirection.rtl, child: child!),
    ),
    home: home,
  ));
  await tester.pump(const Duration(milliseconds: 400));
}

// «مشاركة البيت N»: the three formats hand the right thing to the system share sheet,
// and the manuscript clip is a strip of the scan around the verse.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/ui/share/share_sheet.dart';
import 'package:shatibiyyah/ui/widgets/verse_menu.dart' show verseCopyText;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shatibiyyah/ui/design/tz_theme.dart';

/// Loads assets from the project directory, as the app bundle would.
class _FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(await File(key).readAsBytes());
}

void main() {
  sqfliteFfiInit();
  late Directory support;
  late AppContent content;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('share_test');
    content = await AppContent.open(
      loadAsset: (key) async => ByteData.sublistView(await File(key).readAsBytes()),
      supportDir: support,
      factory: databaseFactoryFfi,
    );
  });

  tearDownAll(() async {
    await content.store.close();
    await support.delete(recursive: true);
  });

  Future<List<ShareParams>> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shared = <ShareParams>[];
    await tester.pumpWidget(MaterialApp(
      theme: tzThemeData(TzTheme.dark),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showShareSheet(context, content, 229, share: (p) async => shared.add(p)),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return shared;
  }

  testWidgets('the card (the default) is shared as a PNG with the copy text', (tester) async {
    final shared = await open(tester);
    expect(find.text('مشاركة البيت ٢٢٩'), findsOneWidget);
    expect(find.byType(VerseCard), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('مشاركة'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    final files = shared.single.files!;
    expect(files.single.mimeType, 'image/png');
    final png = await tester.runAsync(() => files.single.readAsBytes());
    expect(png!.sublist(1, 4), 'PNG'.codeUnits);
    expect(shared.single.text, verseCopyText(content, 229));
    expect(find.text('مشاركة البيت ٢٢٩'), findsNothing); // the sheet closed
  });

  testWidgets('«نص» shares the copy text alone', (tester) async {
    final shared = await open(tester);
    await tester.tap(find.text('نص'));
    await tester.pump();
    expect(find.text('— تيسير الشاطبية'), findsOneWidget);
    await tester.tap(find.text('مشاركة'));
    await tester.pumpAndSettle();
    expect(shared.single.text, verseCopyText(content, 229));
    expect(shared.single.files, isNull);
  });

  test('«مشاركة الصفحة» shares the page as a PNG named by its number and chapter', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final shared = <ShareParams>[];
    await sharePage(content, 19, bundle: _FileBundle(), share: (p) async => shared.add(p));
    final png = await shared.single.files!.single.readAsBytes();
    final image = (await (await ui.instantiateImageCodec(png)).getNextFrame()).image;
    expect((image.width, image.height), (1130, 1735));
    final first = content.layout.versesOnPage(19).first;
    expect(shared.single.text, 'ص ١٩ — ${content.matn.chapterOfVerse(first).shortLabel} · تيسير الشاطبية');
  });

  test('the manuscript clip is the full page width around the verse', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final png = await manuscriptClip(content, 229, bundle: _FileBundle());
    final image = (await (await ui.instantiateImageCodec(png)).getNextFrame()).image;
    final box = content.layout.verseRegion(229).rect;
    expect(image.width, 1130);
    expect(image.height, (box.height + 80).round());
  });
}

// «الإعدادات» and «نسخ احتياطي» (P7): theme and text size are set and kept; the
// rows lead on; a backup is written where the user chooses and a restore merges
// it back, with restored reader settings applied at once.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/app/personal_data.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/backup.dart';
import 'package:shatibiyyah/data/legacy_adapter.dart';
import 'package:shatibiyyah/data/settings_store.dart';
import 'package:shatibiyyah/data/user_store.dart';
import 'package:shatibiyyah/services/preferences_service.dart';
import 'package:shatibiyyah/ui/design/app_theme.dart';
import 'package:shatibiyyah/ui/design/taysir_colors.dart';
import 'package:shatibiyyah/ui/reader/reader_controller.dart';
import 'package:shatibiyyah/ui/shell/backup_screen.dart';
import 'package:shatibiyyah/ui/shell/rumuz_screen.dart';
import 'package:shatibiyyah/ui/shell/settings_screen.dart';
import 'package:shatibiyyah/ui/widgets/page_viewer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory support;
  late AppContent content;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('settings_test');
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

  Future<(ReaderController, PersonalData)> open(WidgetTester tester, Widget Function(ReaderController) home) async {
    SharedPreferences.setMockInitialValues({});
    appTheme.value = ReaderTheme.dark;
    addTearDown(() => appTheme.value = ReaderTheme.dark);
    late ReaderController r;
    late PersonalData personal;
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('settings_user');
      addTearDown(() => dir.delete(recursive: true));
      final user = await UserStore.open(directory: dir.path, factory: databaseFactoryFfi);
      addTearDown(user.close);
      personal = PersonalData(user);
      await personal.load();
      final prefs = await Prefs.create();
      final recording = content.recordings.defaultRecording;
      final windows = await content.windowsFor(recording);
      r = ReaderController(
        content: content,
        recording: recording,
        viewer: PageViewerController(legacyData(content, windows), prefs),
        store: SettingsStore(prefs),
        user: user,
        initialVerse: 226,
      )..personal = personal;
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [TaysirColors.dark]),
      home: Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => home(r))),
    ));
    await tester.pump();
    return (r, personal);
  }

  /// Lets real database work started by a tap finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  testWidgets('theme and text size are set and kept; rows lead on', (tester) async {
    final (r, _) = await open(tester, (r) => SettingsScreen(reader: r));
    await tester.tap(find.text('ورقية'));
    await tester.pump();
    expect(appTheme.value, ReaderTheme.paper);
    expect(r.store!.theme, ReaderTheme.paper);

    await tester.tap(find.text('١٥٠٪'));
    await tester.pump();
    expect(r.textScale, 1.5);
    expect(r.store!.textScale, 1.5);

    await tester.tap(find.text('رموز القراء'));
    await tester.pumpAndSettle();
    expect(find.byType(RumuzScreen), findsOneWidget);
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('نسخ احتياطي واستعادة'));
    await tester.pumpAndSettle();
    expect(find.byType(BackupScreen), findsOneWidget);
  });

  testWidgets('a backup is saved, then restored into another device\'s data', (tester) async {
    String? savedName;
    String? savedText;
    final (r, personal) = await open(
      tester,
      (r) => BackupScreen(
        reader: r,
        save: (name, text) async {
          (savedName, savedText) = (name, text);
          return name;
        },
        open: () async => savedText,
      ),
    );
    expect(find.text('لم تُنشأ نسخة بعد'), findsOneWidget);
    await tester.runAsync(() => personal.saveNote(230, 'قارن بالوافي'));
    r.viewer.prefs.setString('v2.theme', 'paper');

    await tester.tap(find.text('إنشاء نسخة الآن'));
    await settle(tester);
    expect(find.text('حُفظت النسخة'), findsOneWidget);
    expect(savedName, startsWith('shatibiyyah-backup-'));
    expect(decodeBackup(savedText!)['notes'], hasLength(1));
    expect(find.textContaining('آخر نسخة:'), findsOneWidget);

    // «another device»: wipe the note and the theme, then restore.
    await tester.runAsync(() => personal.store.db.delete('notes'));
    await tester.runAsync(personal.load);
    await tester.pumpWidget(const SizedBox()); // a fresh screen, not the old one kept
    final (r2, personal2) = await open(
      tester,
      (r) => BackupScreen(reader: r, save: (_, _) async => null, open: () async => savedText),
    );
    await tester.tap(find.text('استعادة من ملف'));
    await settle(tester);
    expect(find.text('تمت الاستعادة ودُمجت مع ما على الجهاز'), findsOneWidget);
    expect(personal2.noteFor(230)!.body, 'قارن بالوافي');
    expect(appTheme.value, ReaderTheme.paper); // applied at once
    expect(r2.store!.theme, ReaderTheme.paper);

    await tester.tap(find.text('استعادة من ملف'));
    await settle(tester);
    expect(find.text('لا جديد في هذه النسخة'), findsOneWidget);
  });

  testWidgets('any failure clears the spinner and says «تعذّر…» (F-54)', (tester) async {
    final (_, personal) = await open(tester, (r) => BackupScreen(reader: r, save: (name, _) async => name));
    await tester.runAsync(personal.store.close); // the next read throws a DatabaseException
    await tester.tap(find.text('إنشاء نسخة الآن'));
    await settle(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('تعذّر'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.ancestor(of: find.text('إنشاء نسخة الآن'), matching: find.byType(FilledButton))).onPressed,
        isNotNull); // it can be tried again
  });

  testWidgets('a file that is not a backup is refused with a reason', (tester) async {
    await open(tester, (r) => BackupScreen(reader: r, open: () async => '{"hello": 1}'));
    await tester.tap(find.text('استعادة من ملف'));
    await settle(tester);
    expect(find.text('الملف ليس نسخة احتياطية من تيسير الشاطبية'), findsOneWidget);
  });
}

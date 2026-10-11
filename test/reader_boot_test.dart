// The boot (lib/app/reader_boot.dart) over the real bundled snapshot: what it
// hands the app is the same whether its steps run one after another or side by
// side — the reader on the verse it was left on, the student's marks on the page,
// and the reminder planned for that verse.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shatibiyyah/app/reader_boot.dart';
import 'package:shatibiyyah/app/reminders.dart';
import 'package:shatibiyyah/data/user_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  // The host registers no plugins: the Android side of the notifications answers below.
  AndroidFlutterLocalNotificationsPlugin.registerWith();

  const notifications = MethodChannel('dexterous.com/flutter/local_notifications');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory support;
  late List<MethodCall> asked;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('reader_boot_test');
    asked = [];
    messenger.setMockMethodCallHandler(notifications, (call) async {
      asked.add(call);
      return call.method == 'initialize' ? true : null;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(notifications, null);
    await support.delete(recursive: true);
  });

  test('a first launch: verse 1, nothing to play, no marks, no reminder planned', () async {
    SharedPreferences.setMockInitialValues({});
    final pages = <int>[];
    final reader = await bootReader(onFirstPage: pages.add, supportDir: support);
    addTearDown(reader.content.store.close);
    addTearDown(reader.user!.db.close);

    expect(reader.verse, 1);
    expect(pages, [1]);
    expect(reader.audioAvailable, isFalse); // no recording is bundled
    expect(reader.library!.isOnDevice(reader.recording), isFalse);
    expect(reader.personal!.bookmarks, isEmpty);
    expect(reader.reminders, isNotNull);
    expect(asked.map((c) => c.method), isNot(contains('zonedSchedule')));
  });

  test('a later launch: the verse it was left on, its marks, and the reminder for that verse', () async {
    // What an earlier session left: a bookmark in user.sqlite, the verse and the switch in the preferences.
    final user = await UserStore.open(directory: support.path);
    await user.saveBookmark(229, color: BookmarkColor.green, tag: BookmarkTag.muraja);
    await user.db.close();
    SharedPreferences.setMockInitialValues({kSessionVerse: '226', kChapterReminderPref: '1'});

    final pages = <int>[];
    final reader = await bootReader(onFirstPage: pages.add, supportDir: support);
    addTearDown(reader.content.store.close);
    addTearDown(reader.user!.db.close);

    expect(reader.verse, 226);
    expect(pages, [19]); // told once, for the page of the verse it opens on
    expect(reader.personal!.bookmarks.single.fromVerse, 229);
    expect(reader.viewer.ribbons, {229: BookmarkColor.green.index});
    // Planned while the reader was still being built: for the verse it opens on.
    final planned = asked.where((c) => c.method == 'zonedSchedule').toList();
    expect(planned, hasLength(1));
    expect((planned.single.arguments as Map)['payload'], 'verse:226');
    expect(reader.reminders!.chapterOn, isTrue);
  });
}

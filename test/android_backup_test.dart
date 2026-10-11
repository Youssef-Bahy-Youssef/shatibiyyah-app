// What Android's automatic backup keeps: the student's bookmarks and notes, and
// nothing of the install's own state. A restored preferences file made an app
// installed afresh open on the verse of an older install, without the tour; and
// with a recording in the app's files the backup was past Android's 25 MB and
// was skipped whole.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const res = 'android/app/src/main/res/xml';

  /// The file without its comments.
  String read(String path) => File(path).readAsStringSync().replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

  /// Every rule in [xml], as written: «include file user.sqlite».
  List<String> rules(String xml) => [
        for (final m in RegExp(r'<(include|exclude)\s+domain="([^"]*)"\s+path="([^"]*)"\s*/>').allMatches(xml))
          '${m[1]} ${m[2]} ${m[3]}',
      ];

  const userData = ['include file user.sqlite', 'include file user.sqlite-wal', 'include file user.sqlite-journal'];

  test('the manifest names both rule files', () {
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    final app = RegExp(r'<application[^>]*>').firstMatch(manifest)![0]!;
    expect(app, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(app, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    expect(app, isNot(contains('allowBackup="false"')), reason: 'bookmarks and notes are still backed up');
  });

  // With an <include>, Android backs up only what is listed: the preferences
  // (domain «sharedpref»: the verse the reader is on, the tour, the chosen
  // recording), the recordings and the content copy are not.
  test('Android 11 and older: user.sqlite and its journals, nothing else', () {
    final xml = read('$res/backup_rules.xml');
    expect(xml, contains('<full-backup-content>'));
    expect(rules(xml), userData);
  });

  test('Android 12 and newer: the cloud backup keeps the same; a phone-to-phone transfer copies everything', () {
    final xml = read('$res/data_extraction_rules.xml');
    final cloud = RegExp(r'<cloud-backup>([\s\S]*)</cloud-backup>').firstMatch(xml)![1]!;
    expect(rules(cloud), userData);
    expect(rules(xml), userData, reason: 'no rule outside the cloud backup');
    expect(xml, isNot(contains('device-transfer')));
  });

  test('the file the rules name is the one the student\'s data is kept in', () {
    expect(File('lib/data/user_store.dart').readAsStringSync(), contains("String name = 'user.sqlite'"));
  });
}

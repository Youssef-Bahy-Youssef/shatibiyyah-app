// «مراجعك وملاحظاتك تبقى على جهازك» («حول», ADR 0033). The line is a promise, and
// these are the things that would break it without anyone touching the line:
// Android copying the app's files to Google Drive, a package that reports what
// the student does, and a host the app calls that nobody listed.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android\'s backup to Google Drive is off for the whole app', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final application = RegExp(r'<application\b[^>]*>').firstMatch(manifest)!.group(0)!;
    expect(application, contains('android:allowBackup="false"'));
    // With it off nothing may turn part of it back on.
    expect(manifest, isNot(contains('android:fullBackupContent')));
    expect(manifest, isNot(contains('android:backupAgent')));
  });

  test('no package watches the student or reports from the device', () {
    final lock = File('pubspec.lock').readAsStringSync();
    final packages = {for (final m in RegExp(r'^  (\w+):$', multiLine: true).allMatches(lock)) m.group(1)!};
    const reporters = ['firebase', 'google_mobile_ads', 'sentry', 'crashlytics', 'analytics', 'amplitude', 'mixpanel',
        'appsflyer', 'adjust', 'facebook', 'onesignal', 'posthog', 'datadog', 'bugsnag', 'instabug', 'clarity'];
    expect(
      [for (final p in packages) if (reporters.any(p.contains)) p],
      isEmpty,
      reason: 'ADR 0033 says nothing leaves the device unasked: change the record and «حول» before adding one',
    );
  });

  test('the app names no host of its own but the stores\'', () {
    // Recordings come from the hosts the content snapshot lists, and a commentary's
    // source page from the address the snapshot gives it. Anything else the app
    // could reach would be written in lib/, as an address or a host.
    final named = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      for (final (i, line) in file.readAsLinesSync().indexed) {
        final code = line.replaceFirst(RegExp(r'(^|\s)//.*$'), ''); // a comment, not the «//» of an address
        if (RegExp(r'''https?://|Uri\.https?\(|['"]www\.''').hasMatch(code)) named.add('${file.path}:${i + 1}');
      }
    }
    expect(named, everyElement(startsWith('lib/app/app_links.dart:')));
    expect(named, hasLength(3)); // Google Play's page; the App Store's page and its rating page
  });
}

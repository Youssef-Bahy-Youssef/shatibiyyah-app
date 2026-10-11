// Where the app points outside itself (lib/app/app_links.dart, ADR 0033): the
// store page is the one this build's own id names, a platform with no page has
// none, and the letter «أرسل ملاحظة» opens reads in a mail app as it was written.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/app/app_links.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('the store page', () {
    test('Android: the page of the id this build is published under', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(RegExp(r'applicationId = "([\w.]+)"').firstMatch(gradle)!.group(1), kAndroidPackage);

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final links = AppLinks.ofPlatform();
      expect('${links.listing}', 'https://play.google.com/store/apps/details?id=$kAndroidPackage');
      expect(links.review, links.listing);
      expect(links.storeName, 'Google Play');
    });

    test('iOS: none until the App Store has numbered the app; then its page, and its rating page', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final unlisted = AppLinks.ofPlatform(appStoreId: null);
      expect([unlisted.listing, unlisted.review, unlisted.storeName], [null, null, null]);

      final listed = AppLinks.ofPlatform(appStoreId: '1234567890');
      expect('${listed.listing}', 'https://apps.apple.com/app/id1234567890');
      expect('${listed.review}', 'https://apps.apple.com/app/id1234567890?action=write-review');
      expect(listed.storeName, 'App Store');
    });

    test('what is shared is the app\'s name, its line and the page, a line each', () {
      final page = Uri.parse('https://play.google.com/store/apps/details?id=$kAndroidPackage');
      expect(shareAppText(page).split('\n'), ['تيسير الشاطبية', kAppLine, '$page']);
    });
  });

  group('the support address', () {
    test('is an address when there is one, and reaches every platform\'s links', () {
      if (kSupportEmail case final address?) {
        expect(address, matches(RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$')));
      }
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(AppLinks.ofPlatform().supportEmail, kSupportEmail, reason: '$platform');
        expect(AppLinks.ofPlatform(supportEmail: 'a@b.example').supportEmail, 'a@b.example', reason: '$platform');
      }
    });
  });

  group('the letter', () {
    /// A mailto's fields as a mail app reads them: percent-decoded, a «+» left a plus.
    Map<String, String> fields(Uri mail) => {
          for (final field in mail.query.split('&'))
            field.substring(0, field.indexOf('=')): Uri.decodeComponent(field.substring(field.indexOf('=') + 1)),
        };

    test('goes to the address, with its subject and one line about the app under an empty body', () {
      final mail = feedbackMail(
          address: 'taysir@example.org', version: '1.0.0', content: '8b812493', system: 'Google Pixel 8 · Android 16');
      expect(mail.scheme, 'mailto');
      expect(mail.path, 'taysir@example.org');
      expect('$mail', startsWith('mailto:taysir@example.org?subject='));
      final f = fields(mail);
      expect(f.keys, ['subject', 'body']);
      expect(f['subject'], 'ملاحظة على تيسير الشاطبية');
      expect(f['body']!.split('\r\n'), ['', '', '', '—', 'الإصدار 1.0.0 · المحتوى 8b812493 · Google Pixel 8 · Android 16']);
    });

    test('no space is written as a plus, which a mail app would show', () {
      final mail = feedbackMail(address: 'taysir@example.org', version: '1.0.0', system: 'Samsung SM-A525F · Android 13');
      expect(mail.query, isNot(contains('+')));
      expect(mail.query, isNot(contains(' ')));
      expect(fields(mail)['body'], endsWith('الإصدار 1.0.0 · Samsung SM-A525F · Android 13'));
    });

    test('says only what is known', () {
      final f = fields(feedbackMail(address: 'taysir@example.org', version: '1.0.0'));
      expect(f['body'], endsWith('—\r\nالإصدار 1.0.0'));
    });
  });
}

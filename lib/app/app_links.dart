// lib/app/app_links.dart — where the app points outside itself (features-v3
// about-and-support; ADR 0033): the address «أرسل ملاحظة» writes to, and the
// store page «شارك التطبيق» sends and «قيّم التطبيق» opens.
//
// A row on «حول» shows only when its destination exists: links given no address
// have no «أرسل ملاحظة»; on a platform with no store page there is neither «شارك
// التطبيق» nor «قيّم التطبيق».
import 'package:flutter/foundation.dart';

/// The address feedback is written to: the app's own, which the owner made for it
/// on 2026-10-13 in place of a personal one (plan Q12).
const String kSupportEmail = 'taysir.shatibiyyah@gmail.com';

/// The Android application id, which is the app's page on Google Play
/// (test/app_links_test.dart keeps it equal to android/app/build.gradle.kts).
const String kAndroidPackage = 'com.shatibiyyah.app';

/// The App Store's number for the app; null until it is listed there (plan 7.8).
const String? kAppStoreId = null;

/// One line saying what the app is: under its name on «حول», and in what
/// «شارك التطبيق» sends.
const String kAppLine =
    'رفيقك لدراسة متن الشاطبية وحفظها، بتلاوة صوتية بيتًا بيتًا، وشروح تعينك على فهم كل بيت';

class AppLinks {
  /// Where «أرسل ملاحظة» writes.
  final String? supportEmail;

  /// The app's page in this platform's store: what «شارك التطبيق» sends.
  final Uri? listing;

  /// The same page where it asks for a rating: what «قيّم التطبيق» opens.
  final Uri? review;

  /// That store's name, as it names itself.
  final String? storeName;

  const AppLinks({this.supportEmail, this.listing, Uri? review, this.storeName}) : review = review ?? listing;

  /// The links of the platform the app runs on.
  factory AppLinks.ofPlatform({String? supportEmail = kSupportEmail, String? appStoreId = kAppStoreId}) =>
      switch (defaultTargetPlatform) {
        TargetPlatform.android => AppLinks(
            supportEmail: supportEmail,
            listing: Uri.https('play.google.com', '/store/apps/details', {'id': kAndroidPackage}),
            storeName: 'Google Play',
          ),
        TargetPlatform.iOS when appStoreId != null => AppLinks(
            supportEmail: supportEmail,
            listing: Uri.https('apps.apple.com', '/app/id$appStoreId'),
            review: Uri.https('apps.apple.com', '/app/id$appStoreId', {'action': 'write-review'}),
            storeName: 'App Store',
          ),
        _ => AppLinks(supportEmail: supportEmail),
      };
}

/// What «شارك التطبيق» sends: the app's name, its line and its page.
String shareAppText(Uri listing) => 'تيسير الشاطبية\n$kAppLine\n$listing';

/// The letter «أرسل ملاحظة» opens in the mail app: to [address], its subject
/// set, and under the place for the student's words one line a report needs to
/// be acted on: the app's [version], the [content] it carries and the [system]
/// it runs on. The student sees the line before sending and may remove it.
Uri feedbackMail({required String address, required String version, String? content, String? system}) {
  final about = [
    'الإصدار $version',
    if (content != null) 'المحتوى $content',
    ?system,
  ].join(' · ');
  // Not Uri(queryParameters:), which writes a space as «+»: mail apps show the plus.
  // Lines end as RFC 6068 has them.
  final query = {'subject': 'ملاحظة على تيسير الشاطبية', 'body': '\r\n\r\n\r\n—\r\n$about'}
      .entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');
  return Uri(scheme: 'mailto', path: address, query: query);
}

// tool/check_audio_hosts.dart — the recordings' hosts, checked with the app's own
// downloader (DownloadManager + HttpTransfer) over the real network:
//
//   flutter test tool/check_audio_hosts.dart
//
// For every mirror of every recording: a download cut off after 20 MB, then
// resumed — the resumed part must continue from the part file (a Range request
// that survives the host's redirect), and the whole file must match its SHA-256.
// Then a dead first mirror must hand over to the next one. About 1 GB goes over
// the network. It lives in tool/, so `flutter test` without a path skips it.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/data/app_content.dart';
import 'package:shatibiyyah/data/recording_repository.dart';
import 'package:shatibiyyah/services/download_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const int _cutAt = 20 * 1000 * 1000;

Recording _withUrls(Recording r, List<String> urls) => Recording(
      r.id, r.slug, r.reciterId, r.reciterName, r.title, r.attribution, r.isDefault, r.durationMs, r.audioBytes,
      r.audioSha256, r.timebaseStatus, r.timebaseOffsetMs, r.sampleAssetPath, r.licenseNote,
      DeliveryFile(r.delivery!.sha256, r.delivery!.bytes, r.delivery!.durationMs, r.delivery!.contentType, urls),
    );

void main() {
  sqfliteFfiInit();
  late Directory support;
  late AppContent content;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('hosts');
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

  DownloadManager manager(Directory dir) => DownloadManager(
        supportDir: dir,
        freeBytes: () async => null,
        onUnmeteredNetwork: () async => true,
        retryDelay: const Duration(seconds: 1),
      );

  test('every recording has mirrors', () {
    for (final r in content.recordings.recordings) {
      expect(r.delivery, isNotNull, reason: r.slug);
      expect(r.delivery!.urls.length, greaterThanOrEqualTo(2), reason: r.slug);
    }
  });

  for (final slug in ['muhammad-atiq-1', 'abdulhamid-alqaryu-1']) {
    for (final mirror in [0, 1]) {
      test('$slug, mirror ${mirror + 1}: cut at 20 MB, resumed, verified', () async {
        final base = content.recordings.recordings.firstWhere((r) => r.slug == slug);
        final url = base.delivery!.urls[mirror];
        final r = _withUrls(base, [url]);
        final dir = await Directory.systemTemp.createTemp('host_$slug');
        addTearDown(() => dir.delete(recursive: true));
        final dm = manager(dir);

        final cancel = DownloadCancel();
        final watch = Stopwatch()..start();
        await expectLater(
          dm.download(r, wifiOnly: false, cancel: cancel, onProgress: (p) {
            if (p.received >= _cutAt) cancel.cancel();
          }),
          throwsA(isA<DownloadException>().having((e) => e.error, 'error', DownloadError.cancelled)),
        );
        final part = dm.partFileFor(r).lengthSync();
        expect(part, greaterThanOrEqualTo(_cutAt));

        var firstAfterResume = -1;
        final file = await dm.download(r, wifiOnly: false, onProgress: (p) {
          if (firstAfterResume < 0 && p.phase == DownloadPhase.downloading) firstAfterResume = p.received;
        });
        expect(firstAfterResume, greaterThan(part), reason: 'the host restarted instead of resuming: $url');
        expect(file.lengthSync(), r.delivery!.bytes);
        final mb = r.delivery!.bytes / 1e6;
        // ignore: avoid_print
        print('$slug mirror ${mirror + 1}: ${mb.toStringAsFixed(1)} MB verified in '
            '${watch.elapsed.inSeconds} s (${(mb / watch.elapsed.inMilliseconds * 1000).toStringAsFixed(1)} MB/s), '
            'resumed at ${(part / 1e6).toStringAsFixed(1)} MB — $url');
      }, timeout: const Timeout(Duration(minutes: 30)));
    }
  }

  test('a dead first mirror hands over to the next', () async {
    final base = content.recordings.recordings.firstWhere((r) => r.slug == 'muhammad-atiq-1');
    final r = _withUrls(base, ['https://github.com/Youssef-Bahy-Youssef/taysir-audio/releases/download/audio-v1/missing.mp3', ...base.delivery!.urls]);
    final dir = await Directory.systemTemp.createTemp('host_failover');
    addTearDown(() => dir.delete(recursive: true));
    final file = await manager(dir).download(r, wifiOnly: false);
    expect(file.lengthSync(), r.delivery!.bytes);
  }, timeout: const Timeout(Duration(minutes: 30)));
}

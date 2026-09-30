// lib/services/download_manager.dart — a recording onto the device (features-v3
// audio-downloads; recordings are the only downloads).
//
// One file per recording, from the mirrors listed in recording_files (tried in
// order; a failing mirror hands over to the next, which resumes where the last
// stopped). The bytes land in `<file>.part` and resume with an HTTP Range request
// after any interruption, including the app being killed. When the size is
// reached the SHA-256 is checked off the UI thread; a mismatch discards the part
// file and starts once more from nothing. Only a verified file is renamed into
// place, so the reader never sees a partial or corrupted recording.
//
// Before starting: the free space must cover what is left plus 50 MB, and by
// default the download waits for Wi-Fi.
//
// The bytes are moved by a [Transfer]: [HttpTransfer] (dart:io, while the app
// runs; used in tests and where no background service exists) or, on Android,
// BackgroundTransfer (lib/services/background_transfer.dart), which carries on
// after the app is closed. A part file completed while the app was closed is
// verified and moved into place by [DownloadManager.recover] at the next launch.
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:path/path.dart' as p;

import '../data/recording_repository.dart';

/// Free space kept beyond the file itself.
const int kFreeSpaceMargin = 50 * 1024 * 1024;

enum DownloadPhase { waitingForWifi, downloading, verifying, done, failed, cancelled }

enum DownloadError { noUrls, noSpace, network, verification, cancelled }

class DownloadProgress {
  final DownloadPhase phase;
  final int received;
  final int total;
  final DownloadError? error;
  const DownloadProgress(this.phase, this.received, this.total, [this.error]);
  double get fraction => total == 0 ? 0 : received / total;
}

class DownloadException implements Exception {
  final DownloadError error;
  const DownloadException(this.error);
  @override
  String toString() => 'DownloadException($error)';
}

/// Lets a caller stop a download; the part file stays for the next attempt.
class DownloadCancel {
  bool _cancelled = false;
  final _listeners = <void Function()>[];
  bool get cancelled => _cancelled;
  void cancel() {
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  /// [listener] runs when [cancel] is called (a transfer that is not polling).
  void onCancel(void Function() listener) => _listeners.add(listener);
}

/// Thrown by a [Transfer] when its [DownloadCancel] was used.
class TransferCancelled implements Exception {
  const TransferCancelled();
}

/// Moves the bytes of one mirror into the part file.
abstract class Transfer {
  /// Brings [part] to [total] bytes from [url], resuming what is there when it
  /// can, reporting the bytes received. Throws on failure (the manager then tries
  /// the next mirror) and [TransferCancelled] when [cancel] is used.
  Future<void> fetch(Uri url, File part, int total, void Function(int received) progress, DownloadCancel? cancel,
      {required bool wifiOnly});
}

class DownloadManager {
  final Directory supportDir;

  /// Free bytes on the volume of [supportDir]; null when the platform cannot say.
  final Future<int?> Function() freeBytes;

  /// Whether the device is on Wi-Fi (or Ethernet) now.
  final Future<bool> Function() onUnmeteredNetwork;

  /// Rounds over all mirrors before giving up, and the pause between rounds.
  final int rounds;
  final Duration retryDelay;

  final Transfer transfer;

  DownloadManager({
    required this.supportDir,
    required this.freeBytes,
    required this.onUnmeteredNetwork,
    this.rounds = 3,
    this.retryDelay = const Duration(seconds: 2),
    Transfer? transfer,
    HttpClient Function()? httpClient,
  }) : transfer = transfer ?? HttpTransfer(httpClient ?? HttpClient.new);

  File fileFor(Recording r) => File(p.join(supportDir.path, RecordingRepository.localFileName(r)));
  File _partFor(Recording r) => File('${fileFor(r).path}.part');

  /// Where [r]'s bytes gather until verified.
  File partFileFor(Recording r) => _partFor(r);

  /// Whether [r] is on the device, complete.
  Future<bool> isDownloaded(Recording r) async {
    final f = fileFor(r);
    return await f.exists() && await f.length() == r.localBytes;
  }

  /// Removes [r] from the device (and any part file).
  Future<void> delete(Recording r) async {
    for (final f in [fileFor(r), _partFor(r)]) {
      if (await f.exists()) await f.delete();
    }
  }

  /// A part file that reached its full size while the app was closed (a
  /// background transfer finished): verified and moved into place. True when [r]
  /// is now on the device; a corrupted part file is discarded.
  Future<bool> recover(Recording r) async {
    final delivery = r.delivery;
    final part = _partFor(r);
    if (delivery == null || !await part.exists() || await part.length() != delivery.bytes) return false;
    if (await compute(_sha256Of, part.path) != delivery.sha256) {
      await part.delete();
      return false;
    }
    await part.rename(fileFor(r).path);
    return true;
  }

  /// Downloads [r], reporting progress; returns the verified file.
  Future<File> download(
    Recording r, {
    bool wifiOnly = true,
    void Function(DownloadProgress)? onProgress,
    DownloadCancel? cancel,
    Duration wifiPoll = const Duration(seconds: 5),
  }) async {
    final delivery = r.delivery;
    if (delivery == null || delivery.urls.isEmpty) throw const DownloadException(DownloadError.noUrls);
    final total = delivery.bytes;
    void report(DownloadPhase phase, int received, [DownloadError? e]) =>
        onProgress?.call(DownloadProgress(phase, received, total, e));

    final target = fileFor(r);
    if (await isDownloaded(r)) {
      report(DownloadPhase.done, total);
      return target;
    }
    await target.parent.create(recursive: true);
    final part = _partFor(r);

    Future<int> have() async => await part.exists() ? await part.length() : 0;

    final free = await freeBytes();
    if (free != null && free < total - await have() + kFreeSpaceMargin) {
      report(DownloadPhase.failed, await have(), DownloadError.noSpace);
      throw const DownloadException(DownloadError.noSpace);
    }

    var verifiedOnce = false;
    for (var round = 0; round < rounds; round++) {
      for (final url in delivery.urls) {
        while (wifiOnly && !await onUnmeteredNetwork()) {
          if (cancel?.cancelled ?? false) {
            report(DownloadPhase.cancelled, await have());
            throw const DownloadException(DownloadError.cancelled);
          }
          report(DownloadPhase.waitingForWifi, await have());
          await Future<void>.delayed(wifiPoll);
        }
        try {
          await transfer.fetch(Uri.parse(url), part, total, (n) => report(DownloadPhase.downloading, n), cancel,
              wifiOnly: wifiOnly);
        } on TransferCancelled {
          report(DownloadPhase.cancelled, await have());
          throw const DownloadException(DownloadError.cancelled);
        } catch (_) {
          continue; // this mirror failed; the next one resumes from the part file
        }
        if (await have() != total) continue;

        report(DownloadPhase.verifying, total);
        // compute() sends only the function and the path; a closure would carry its
        // whole context to the isolate.
        final digest = await compute(_sha256Of, part.path);
        if (digest == delivery.sha256) {
          await part.rename(target.path);
          report(DownloadPhase.done, total);
          return target;
        }
        // Corrupted: throw the bytes away and fetch them once more from nothing.
        await part.delete();
        if (verifiedOnce) {
          report(DownloadPhase.failed, 0, DownloadError.verification);
          throw const DownloadException(DownloadError.verification);
        }
        verifiedOnce = true;
      }
      if (round < rounds - 1) await Future<void>.delayed(retryDelay);
    }
    report(DownloadPhase.failed, await have(), DownloadError.network);
    throw const DownloadException(DownloadError.network);
  }

}

/// The transfer over dart:io: appends the rest of the file to the part file with
/// an HTTP Range request. Runs while the app runs.
class HttpTransfer implements Transfer {
  final HttpClient Function() httpClient;
  HttpTransfer(this.httpClient);

  @override
  Future<void> fetch(Uri url, File part, int total, void Function(int) progress, DownloadCancel? cancel,
      {required bool wifiOnly}) async {
    final client = httpClient();
    try {
      var start = await part.exists() ? await part.length() : 0;
      if (start >= total) return;
      final request = await client.getUrl(url);
      if (start > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-');
      final response = await request.close();
      final FileMode mode;
      if (response.statusCode == HttpStatus.partialContent && start > 0) {
        mode = FileMode.append;
      } else if (response.statusCode == HttpStatus.ok) {
        start = 0; // the server ignored the range: start over
        mode = FileMode.write;
      } else {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      final sink = part.openWrite(mode: mode);
      var received = start;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          progress(received);
          if (cancel?.cancelled ?? false) throw const TransferCancelled();
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
    } finally {
      client.close(force: true);
    }
  }
}

String _sha256Of(String path) {
  final sink = _DigestSink();
  final input = sha256.startChunkedConversion(sink);
  final file = File(path).openSync();
  try {
    final buffer = List<int>.filled(1 << 20, 0);
    while (true) {
      final n = file.readIntoSync(buffer);
      if (n == 0) break;
      input.add(buffer.sublist(0, n));
    }
  } finally {
    file.closeSync();
  }
  input.close();
  return sink.value.toString();
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

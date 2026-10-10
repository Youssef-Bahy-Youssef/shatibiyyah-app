// lib/services/download_manager.dart — a recording onto the device (features-v3
// audio-downloads; recordings are the only downloads).
//
// One file per recording, from the mirrors listed in recording_files (tried in
// order; a failing mirror hands over to the next, which resumes where the last
// stopped). The bytes land in `<file>.part` and resume with an HTTP Range request
// after any interruption, including the app being killed or «إيقاف مؤقت». When the
// size is reached the SHA-256 is checked off the UI thread; a mismatch discards the
// part file and starts once more from nothing. Only a verified file is renamed into
// place, so the reader never sees a partial or corrupted recording.
//
// A hash cannot be checked on partial bytes, so a partial is tied to the delivery
// file it was started for (ADR 0007): the sidecar `<slug>.part.json` records its
// delivery_sha256 and size, the bytes received and whether it was paused. A partial
// resumes only when the sidecar names the snapshot's delivery file, it is shorter
// than that file, and the server's 206 total is that file's size; otherwise it is
// discarded and the download starts over.
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
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:path/path.dart' as p;

import '../data/recording_repository.dart';

/// Free space kept beyond the file itself.
const int kFreeSpaceMargin = 50 * 1024 * 1024;

enum DownloadPhase { waitingForWifi, downloading, verifying, done, failed, cancelled, paused }

enum DownloadError { noUrls, noSpace, network, verification, cancelled, paused }

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

/// Lets a caller stop a download: [cancel] stops it (the part file stays for the
/// next attempt), [pause] («إيقاف مؤقت») stops it so that «متابعة» resumes it.
class DownloadCancel {
  bool _cancelled = false;
  bool _paused = false;
  final _listeners = <void Function()>[];
  final _pauseListeners = <void Function()>[];
  bool get cancelled => _cancelled;
  bool get paused => _paused;

  /// Whether the transfer should stop now, for either reason.
  bool get stopped => _cancelled || _paused;

  void cancel() {
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void pause() {
    if (stopped) return;
    _paused = true;
    for (final l in List.of(_pauseListeners)) {
      l();
    }
  }

  /// [listener] runs when [cancel] is called (a transfer that is not polling).
  void onCancel(void Function() listener) => _listeners.add(listener);

  /// [listener] runs when [pause] is called (a transfer that is not polling).
  void onPause(void Function() listener) => _pauseListeners.add(listener);
}

/// Thrown by a [Transfer] when its [DownloadCancel] was used (cancelled or paused).
class TransferCancelled implements Exception {
  const TransferCancelled();
}

/// Thrown by a [Transfer] when the server's total is not the delivery file's size:
/// it serves another file, and the bytes it sent are worthless.
class TransferSizeMismatch implements Exception {
  final int served;
  const TransferSizeMismatch(this.served);
  @override
  String toString() => 'TransferSizeMismatch($served)';
}

/// Moves the bytes of one mirror into the part file.
abstract class Transfer {
  /// Brings [part] to [total] bytes from [url], resuming what is there when it
  /// can, reporting the bytes received. Throws on failure (the manager then tries
  /// the next mirror), [TransferCancelled] when [cancel] is used, and
  /// [TransferSizeMismatch] when the server's total is not [total].
  Future<void> fetch(Uri url, File part, int total, void Function(int received) progress, DownloadCancel? cancel,
      {required bool wifiOnly});

  /// Throws away what the transfer keeps for [part] outside the part file (a
  /// paused task and its temporary file).
  Future<void> discard(File part) async {}
}

/// What an unfinished download left on the device.
class PartialDownload {
  final int received;
  final bool paused;
  const PartialDownload(this.received, {required this.paused});
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

  /// `<slug>.part.json`: the delivery file a partial was started for.
  File _sidecarFor(Recording r) => File(p.setExtension(fileFor(r).path, '.part.json'));

  Future<Map<String, Object?>?> _readSidecar(Recording r) async {
    try {
      final json = jsonDecode(await _sidecarFor(r).readAsString());
      return json is Map<String, Object?> ? json : null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeSidecar(Recording r, int received, {required bool paused}) async {
    final delivery = r.delivery!;
    await _sidecarFor(r).writeAsString(jsonEncode({
      'delivery_sha256': delivery.sha256,
      'delivery_bytes': delivery.bytes,
      'received': received,
      'paused': paused,
    }));
  }

  /// What is kept of an unfinished download of [r] for the snapshot's delivery
  /// file; null when nothing is, or when what is kept was started for another file.
  Future<PartialDownload?> partialOf(Recording r) async {
    final delivery = r.delivery;
    final sidecar = await _readSidecar(r);
    if (delivery == null || sidecar == null) return null;
    if (sidecar['delivery_sha256'] != delivery.sha256 || sidecar['delivery_bytes'] != delivery.bytes) return null;
    final part = _partFor(r);
    final onDisk = await part.exists() ? await part.length() : 0;
    final received = max(onDisk, (sidecar['received'] as num?)?.toInt() ?? 0);
    if (received > delivery.bytes) return null;
    return PartialDownload(received, paused: sidecar['paused'] == true);
  }

  /// Throws away every byte of [r] that is not a verified file: the part file, the
  /// sidecar and what the transfer keeps.
  Future<void> _discardPartial(Recording r) async {
    final part = _partFor(r);
    await transfer.discard(part);
    for (final f in [part, _sidecarFor(r)]) {
      if (await f.exists()) await f.delete();
    }
  }

  /// Whether [r] is on the device, complete.
  Future<bool> isDownloaded(Recording r) async {
    final f = fileFor(r);
    return await f.exists() && await f.length() == r.localBytes;
  }

  /// Removes [r] from the device in any state: the verified file, a partial, its
  /// sidecar and anything the transfer keeps for it.
  Future<void> delete(Recording r) async {
    await _discardPartial(r);
    final f = fileFor(r);
    if (await f.exists()) await f.delete();
  }

  final Map<String, Future<bool>> _recovering = {};

  /// A part file that reached its full size while the app was closed (a
  /// background transfer finished): verified and moved into place. True when [r]
  /// is now on the device; a corrupted part file is discarded. One check runs at a
  /// time per recording: a second caller (refresh at launch and a background
  /// download's completion can meet here) awaits the first (F-34).
  Future<bool> recover(Recording r) =>
      // A block body: `=> remove(...)` would return this very future, and
      // whenComplete would wait for it forever.
      _recovering[r.id] ??= _recover(r).whenComplete(() {
        _recovering.remove(r.id);
      });

  Future<bool> _recover(Recording r) async {
    final delivery = r.delivery;
    final part = _partFor(r);
    if (delivery == null || !await part.exists() || await part.length() != delivery.bytes) return false;
    if (await compute(_sha256Of, part.path) != delivery.sha256) {
      await _discardPartial(r);
      return false;
    }
    await part.rename(fileFor(r).path);
    if (await _sidecarFor(r).exists()) await _sidecarFor(r).delete();
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

    // A partial resumes only for the delivery file it was started for.
    final kept = await partialOf(r);
    if (kept == null) await _discardPartial(r);
    var received = kept?.received ?? 0;
    await _writeSidecar(r, received, paused: false);

    // The part file on dart:io; a background transfer's bytes stay in its own
    // temporary file until complete, so its progress counts instead.
    Future<int> have() async => await part.exists() ? await part.length() : received;

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
          if (cancel?.paused ?? false) {
            await _writeSidecar(r, await have(), paused: true);
            report(DownloadPhase.paused, await have());
            throw const DownloadException(DownloadError.paused);
          }
          report(DownloadPhase.waitingForWifi, await have());
          await Future<void>.delayed(wifiPoll);
        }
        try {
          await transfer.fetch(Uri.parse(url), part, total, (n) {
            received = n;
            report(DownloadPhase.downloading, n);
          }, cancel, wifiOnly: wifiOnly);
        } on TransferCancelled {
          final paused = cancel?.paused ?? false;
          await _writeSidecar(r, await have(), paused: paused);
          report(paused ? DownloadPhase.paused : DownloadPhase.cancelled, await have());
          throw DownloadException(paused ? DownloadError.paused : DownloadError.cancelled);
        } on TransferSizeMismatch {
          // This mirror serves another file: its bytes are worthless.
          await _discardPartial(r);
          received = 0;
          await _writeSidecar(r, 0, paused: false);
          continue;
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
          await _sidecarFor(r).delete();
          report(DownloadPhase.done, total);
          return target;
        }
        // Corrupted: throw the bytes away and fetch them once more from nothing.
        await part.delete();
        received = 0;
        if (verifiedOnce) {
          await _discardPartial(r);
          report(DownloadPhase.failed, 0, DownloadError.verification);
          throw const DownloadException(DownloadError.verification);
        }
        await _writeSidecar(r, 0, paused: false);
        verifiedOnce = true;
      }
      if (round < rounds - 1) await Future<void>.delayed(retryDelay);
    }
    await _writeSidecar(r, await have(), paused: false);
    report(DownloadPhase.failed, await have(), DownloadError.network);
    throw const DownloadException(DownloadError.network);
  }

}

/// The transfer over dart:io: appends the rest of the file to the part file with
/// an HTTP Range request. Runs while the app runs.
class HttpTransfer extends Transfer {
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
        // «bytes 1000-1999/2000»: the total must be the delivery file's size.
        final range = response.headers.value(HttpHeaders.contentRangeHeader);
        final served = int.tryParse(RegExp(r'/(\d+)$').firstMatch(range ?? '')?.group(1) ?? '');
        if (served != total) {
          await response.drain<void>();
          throw TransferSizeMismatch(served ?? -1);
        }
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
          if (cancel?.stopped ?? false) throw const TransferCancelled();
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

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
// default the download waits for Wi-Fi. Each thing it can wait on or fail for has
// its own state (ADR 0007): no network (it goes on by itself when one is back),
// no Wi-Fi (the listener may let this one download use mobile data), a full disk
// (seen before the start, and again when a write fails), a file that does not
// verify. A mirror whose file has another size is skipped; the bytes already here
// go on with the next one.
//
// A verified file gets a marker naming the delivery file it is (`<slug>.ok`). When
// an app update brings a new recording, the old file no longer matches the
// snapshot: it is not «on the device» and is never played ([needsUpdate]).
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

enum DownloadPhase { waitingForNetwork, waitingForWifi, downloading, verifying, done, failed, cancelled, paused }

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
  bool _metered = false;
  Completer<void> _changed = Completer<void>();
  final _listeners = <void Function()>[];
  final _pauseListeners = <void Function()>[];
  bool get cancelled => _cancelled;
  bool get paused => _paused;

  /// Whether the transfer should stop now, for either reason.
  bool get stopped => _cancelled || _paused;

  /// «نزّل عبر البيانات»: this one download may use a metered network.
  bool get metered => _metered;

  void _wake() {
    final changed = _changed;
    _changed = Completer<void>();
    changed.complete();
  }

  /// Completes at the next call of [cancel], [pause] or [allowMetered]: a wait
  /// (for Wi-Fi, for a network) ends at once instead of at its next poll.
  Future<void> get changed => _changed.future;

  void cancel() {
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
    _wake();
  }

  void pause() {
    if (stopped) return;
    _paused = true;
    for (final l in List.of(_pauseListeners)) {
      l();
    }
    _wake();
  }

  void allowMetered() {
    _metered = true;
    _wake();
  }

  /// [listener] runs when [cancel] is called (a transfer that is not polling).
  /// One added after the call does not run: look at [cancelled] as well.
  void onCancel(void Function() listener) => _listeners.add(listener);

  /// [listener] runs when [pause] is called (a transfer that is not polling).
  /// One added after the call does not run: look at [paused] as well.
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

  /// Whether the device has a network at all now (true when the platform cannot say).
  final Future<bool> Function() online;

  /// Rounds over all mirrors before giving up, and the pause between rounds.
  final int rounds;
  final Duration retryDelay;

  /// How often a download waiting for a network looks again.
  final Duration networkPoll;

  final Transfer transfer;

  DownloadManager({
    required this.supportDir,
    required this.freeBytes,
    required this.onUnmeteredNetwork,
    Future<bool> Function()? online,
    this.rounds = 3,
    this.retryDelay = const Duration(seconds: 2),
    this.networkPoll = const Duration(seconds: 5),
    Transfer? transfer,
    HttpClient Function()? httpClient,
  })  : online = online ?? _alwaysOnline,
        transfer = transfer ?? HttpTransfer(httpClient ?? HttpClient.new);

  static Future<bool> _alwaysOnline() async => true;

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

  /// `<slug>.ok`: the SHA-256 of the delivery file the verified file is.
  File _markerFor(Recording r) => File(p.setExtension(fileFor(r).path, '.ok'));

  Future<String?> _verifiedAs(Recording r) async {
    try {
      return (await _markerFor(r).readAsString()).trim();
    } on FileSystemException {
      return null;
    }
  }

  String _hashOf(Recording r) => r.delivery?.sha256 ?? r.audioSha256;

  /// Whether [r] is on the device, complete, and the file the snapshot names. A
  /// file from before the markers counts by its size ([adoptVerified] marks it).
  Future<bool> isDownloaded(Recording r) async {
    final f = fileFor(r);
    if (!await f.exists() || await f.length() != r.localBytes) return false;
    final verified = await _verifiedAs(r);
    return verified == null || verified == _hashOf(r);
  }

  /// A file is there for [r], but not the one the snapshot names now (an app
  /// update brought a new recording): it must be downloaded again, and is not played.
  Future<bool> needsUpdate(Recording r) async => await fileFor(r).exists() && !await isDownloaded(r);

  /// Marks a complete file that has no marker yet (verified before the markers
  /// existed) as the snapshot's file, so that a later change of hash is seen.
  Future<void> adoptVerified(Recording r) async {
    if (await isDownloaded(r) && await _verifiedAs(r) == null) await _markerFor(r).writeAsString(_hashOf(r));
  }

  /// Removes [r] from the device in any state: the verified file, a partial, its
  /// sidecar and anything the transfer keeps for it.
  Future<void> delete(Recording r) async {
    await _discardPartial(r);
    for (final f in [fileFor(r), _markerFor(r)]) {
      if (await f.exists()) await f.delete();
    }
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
    await _markerFor(r).writeAsString(delivery.sha256);
    if (await _sidecarFor(r).exists()) await _sidecarFor(r).delete();
    return true;
  }

  /// Whether a failed write means the disk is full: the system says so (ENOSPC),
  /// or what is left no longer fits.
  Future<bool> _diskFull(FileSystemException e, int stillNeeded) async {
    if (e.osError?.errorCode == 28) return true;
    final free = await freeBytes();
    return free != null && free < stillNeeded;
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
    // A file verified for another delivery file (an app update): it goes first,
    // so its space is free for the new one.
    if (await needsUpdate(r)) {
      await target.delete();
      if (await _markerFor(r).exists()) await _markerFor(r).delete();
    }
    final part = _partFor(r);

    // A partial resumes only for the delivery file it was started for.
    final kept = await partialOf(r);
    if (kept == null) await _discardPartial(r);
    var received = kept?.received ?? 0;
    await _writeSidecar(r, received, paused: false);

    // The part file on dart:io; a background transfer's bytes stay in its own
    // temporary file until complete, so its progress counts instead.
    Future<int> have() async => await part.exists() ? await part.length() : received;

    Future<Never> full() async {
      await _writeSidecar(r, await have(), paused: false);
      report(DownloadPhase.failed, await have(), DownloadError.noSpace);
      throw const DownloadException(DownloadError.noSpace);
    }

    final free = await freeBytes();
    if (free != null && free < total - await have() + kFreeSpaceMargin) await full();

    // A cancel or a pause used while no transfer is running (before the first,
    // between mirrors, waiting for Wi-Fi) reaches no listener and is not polled
    // for: the manager stops here.
    Future<Never> stop() async {
      if (cancel!.cancelled) {
        report(DownloadPhase.cancelled, await have());
        throw const DownloadException(DownloadError.cancelled);
      }
      await _writeSidecar(r, await have(), paused: true);
      report(DownloadPhase.paused, await have());
      throw const DownloadException(DownloadError.paused);
    }

    // A wait ends at its next look, or at once when the listener acts.
    Future<void> pauseFor(Duration d) => cancel == null ? Future<void>.delayed(d) : Future.any([Future<void>.delayed(d), cancel.changed]);

    // «Wi-Fi only», unless the listener let this one download use mobile data.
    bool keepToWifi() => wifiOnly && !(cancel?.metered ?? false);

    var verifiedOnce = false;
    var round = 0;
    while (round < rounds) {
      var waitedForNetwork = false;
      for (final url in delivery.urls) {
        // No network: it waits, and goes on by itself when one is back.
        while (!await online()) {
          if (cancel?.stopped ?? false) await stop();
          waitedForNetwork = true;
          report(DownloadPhase.waitingForNetwork, await have());
          await pauseFor(networkPoll);
        }
        while (keepToWifi() && !await onUnmeteredNetwork()) {
          if (cancel?.stopped ?? false) await stop();
          report(DownloadPhase.waitingForWifi, await have());
          await pauseFor(wifiPoll);
        }
        // Checked with no await before the fetch: a transfer listens from its first line.
        if (cancel?.stopped ?? false) await stop();
        try {
          await transfer.fetch(Uri.parse(url), part, total, (n) {
            received = n;
            report(DownloadPhase.downloading, n);
          }, cancel, wifiOnly: keepToWifi());
        } on TransferCancelled {
          final paused = cancel?.paused ?? false;
          await _writeSidecar(r, await have(), paused: paused);
          report(paused ? DownloadPhase.paused : DownloadPhase.cancelled, await have());
          throw DownloadException(paused ? DownloadError.paused : DownloadError.cancelled);
        } on TransferSizeMismatch {
          // This mirror has another file: it is skipped. What is here stays for the
          // next one (a transfer that keeps its own temporary file has dropped it).
          received = await part.exists() ? await part.length() : 0;
          await _writeSidecar(r, received, paused: false);
          continue;
        } on FileSystemException catch (e) {
          // A write failed. A full disk is its own state; anything else counts
          // against this mirror.
          if (await _diskFull(e, total - await have())) await full();
          continue;
        } catch (_) {
          // This mirror failed; the next one resumes from the part file. If the
          // network went, the round is not spent: the wait above takes over.
          if (!await online()) waitedForNetwork = true;
          continue;
        }
        if (await have() != total) continue;

        report(DownloadPhase.verifying, total);
        // compute() sends only the function and the path; a closure would carry its
        // whole context to the isolate.
        final digest = await compute(_sha256Of, part.path);
        if (digest == delivery.sha256) {
          await part.rename(target.path);
          await _markerFor(r).writeAsString(delivery.sha256);
          await _sidecarFor(r).delete();
          report(DownloadPhase.done, total);
          return target;
        }
        // Corrupted: throw the bytes away and fetch them once more from nothing,
        // from the next mirror.
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
      if (!waitedForNetwork) round++;
      if (round < rounds) await pauseFor(retryDelay);
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
        // A whole file: it must be the delivery file's size, or nothing here is touched.
        if (response.contentLength >= 0 && response.contentLength != total) {
          await response.drain<void>();
          throw TransferSizeMismatch(response.contentLength);
        }
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

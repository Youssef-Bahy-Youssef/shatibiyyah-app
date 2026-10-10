// The recording downloader against a local HTTP server with fault injection
// (plan P5 acceptance: resume after a kill, next mirror on failure, a corrupted
// byte fails verification and the retry works, low disk, Wi-Fi only); a part
// file finished while the app was closed is recovered; any Transfer plugs in.
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/data/recording_repository.dart';
import 'package:shatibiyyah/services/download_manager.dart';

/// A transfer that writes the whole file at once, or waits until cancelled.
class _InstantTransfer extends Transfer {
  final Uint8List body;
  final bool hang;
  int fetches = 0;

  /// Whether the last fetch was told to keep to Wi-Fi.
  bool? wifiOnly;

  /// Thrown by the next fetch, once (a write that fails).
  Object? failWith;

  /// Completes when a hanging fetch has its cancel listener in place.
  final listening = Completer<void>();
  _InstantTransfer(this.body, {this.hang = false});
  @override
  Future<void> fetch(Uri url, File part, int total, void Function(int) progress, DownloadCancel? cancel,
      {required bool wifiOnly}) async {
    fetches++;
    this.wifiOnly = wifiOnly;
    if (failWith case final error?) {
      failWith = null;
      await part.writeAsBytes(body.sublist(0, 1000)); // what reached the disk before it failed
      throw error;
    }
    if (hang) {
      final cancelled = Completer<void>();
      cancel?.onCancel(cancelled.complete);
      listening.complete();
      await cancelled.future; // like a background task: no polling, only the cancel call
      throw const TransferCancelled();
    }
    await part.writeAsBytes(body);
    progress(total);
  }
}

/// Serves [body] at several paths, each with its own misbehaviour.
class _Server {
  final Uint8List body;
  late final HttpServer _server;
  final ranges = <String>[]; // "path start" per request
  int corruptLeft = 1; // /corrupt flips a byte this many times
  final dropAfter = <String, int>{}; // path -> close the connection after n bytes
  void Function(String path)? onRequest; // runs when a request arrives, before its answer

  _Server(this.body);

  String url(String path) => 'http://${_server.address.host}:${_server.port}$path';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    final range = req.headers.value(HttpHeaders.rangeHeader);
    final start = range == null ? 0 : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
    ranges.add('$path $start');
    onRequest?.call(path);
    final res = req.response;
    if (path == '/fail') {
      res.statusCode = 500;
      await res.close();
      return;
    }
    if (path == '/416' && start > 0) {
      res.statusCode = HttpStatus.requestedRangeNotSatisfiable; // it has a shorter file
      await res.close();
      return;
    }
    if (path == '/wrongfull') {
      // Ignores the range and sends a whole file of another size.
      res.statusCode = HttpStatus.ok;
      res.contentLength = body.length + 7;
      res.add(Uint8List(body.length + 7));
      await res.close();
      return;
    }
    var from = start;
    if (path == '/norange') from = 0;
    res.statusCode = from > 0 ? HttpStatus.partialContent : HttpStatus.ok;
    res.contentLength = body.length - from;
    if (from > 0) {
      // /othersize serves another file under the same name: its total is not the delivery size.
      final total = path == '/othersize' ? body.length + 1 : body.length;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $from-${body.length - 1}/$total');
    }
    var bytes = Uint8List.sublistView(body, from);
    if (path == '/corrupt' && corruptLeft > 0) {
      corruptLeft--;
      bytes = Uint8List.fromList(bytes)..[bytes.length ~/ 2] ^= 0xFF;
    }
    final drop = dropAfter.remove(path);
    if (drop != null) {
      final socket = await res.detachSocket(writeHeaders: true);
      socket.add(bytes.sublist(0, drop));
      await socket.flush();
      socket.destroy(); // the connection dies mid-file
      return;
    }
    if (path == '/slow') {
      for (var i = 0; i < bytes.length; i += 16 * 1024) {
        res.add(bytes.sublist(i, min(i + 16 * 1024, bytes.length)));
        await res.flush(); // arrives in pieces, as over a real network
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await res.close();
      return;
    }
    res.add(bytes);
    await res.close();
  }

  Future<void> close() => _server.close(force: true);
}

Recording _recording(Uint8List body, List<String> urls) => Recording(
      'recording:test', 'test-reciter', 'reciter:test', 'قارئ', 'تلاوة', null, true, 60000, body.length,
      sha256.convert(body).toString(), 'verified', null, null, null,
      DeliveryFile(sha256.convert(body).toString(), body.length, 60000, 'audio/mpeg', urls),
    );

void main() {
  late Directory dir;
  late _Server server;
  late Uint8List body;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('downloads');
    body = Uint8List.fromList(List.generate(300 * 1024, (i) => Random(7).nextInt(256) ^ (i & 0xFF)));
    server = _Server(body);
    await server.start();
  });

  tearDown(() async {
    await server.close();
    await dir.delete(recursive: true);
  });

  DownloadManager manager({int? free, Future<bool> Function()? wifi, Future<bool> Function()? online, Transfer? transfer}) =>
      DownloadManager(
        supportDir: dir,
        freeBytes: () async => free,
        onUnmeteredNetwork: wifi ?? () async => true,
        online: online,
        retryDelay: Duration.zero,
        networkPoll: Duration.zero,
        transfer: transfer,
      );

  test('downloads, verifies and renames into place; reports progress', () async {
    final r = _recording(body, [server.url('/ok')]);
    final phases = <DownloadPhase>[];
    final file = await manager().download(r, onProgress: (p) => phases.add(p.phase));
    expect(await file.readAsBytes(), body);
    expect(File('${file.path}.part').existsSync(), isFalse);
    expect(phases, containsAllInOrder([DownloadPhase.downloading, DownloadPhase.verifying, DownloadPhase.done]));
    expect(await manager().isDownloaded(r), isTrue);
  });

  test('a failing mirror hands over to the next', () async {
    final r = _recording(body, [server.url('/fail'), server.url('/ok')]);
    final file = await manager().download(r);
    expect(await file.readAsBytes(), body);
    expect(server.ranges, ['/fail 0', '/ok 0']);
  });

  test('a connection dropped mid-file resumes on the next mirror with a Range request', () async {
    server.dropAfter['/a'] = 100 * 1024;
    final r = _recording(body, [server.url('/a'), server.url('/b')]);
    final file = await manager().download(r);
    expect(await file.readAsBytes(), body);
    expect(server.ranges, ['/a 0', '/b ${100 * 1024}']);
  });

  test('a download stopped part-way (the app killed) resumes from the part file', () async {
    final r = _recording(body, [server.url('/slow')]);
    final cancel = DownloadCancel();
    await expectLater(
      manager().download(r, cancel: cancel, onProgress: (p) {
        if (p.received > 50 * 1024) cancel.cancel();
      }),
      throwsA(isA<DownloadException>().having((e) => e.error, 'error', DownloadError.cancelled)),
    );
    final part = File('${manager().fileFor(r).path}.part');
    final kept = part.lengthSync();
    expect(kept, greaterThan(0));

    final file = await manager().download(r);
    expect(await file.readAsBytes(), body);
    expect(server.ranges.last, '/slow $kept');
  });

  test('a cancel while a mirror is failing stops the download: the next mirror is not asked', () async {
    final r = _recording(body, [server.url('/fail'), server.url('/ok')]);
    final cancel = DownloadCancel();
    server.onRequest = (_) => cancel.cancel(); // no byte arrives for the transfer to notice it on
    await expectLater(
      manager().download(r, cancel: cancel),
      throwsA(isA<DownloadException>().having((e) => e.error, 'error', DownloadError.cancelled)),
    );
    expect(server.ranges, ['/fail 0']);
  });

  // ADR 0007: a mirror whose size differs is skipped. The bytes already on the
  // device stay: they are tied to the delivery file, and the full hash decides.
  group('a mirror with the wrong size is skipped; the partial goes on with the next one', () {
    for (final (what, path) in [
      ('a 206 whose total is not the delivery size', '/othersize'),
      ('a 416: its file is shorter', '/416'),
      ('a whole file of another size', '/wrongfull'),
    ]) {
      test(what, () async {
        server.dropAfter['/a'] = 100 * 1024;
        final r = _recording(body, [server.url('/a'), server.url(path), server.url('/ok')]);
        final file = await manager().download(r);
        expect(await file.readAsBytes(), body);
        expect(server.ranges, ['/a 0', '$path ${100 * 1024}', '/ok ${100 * 1024}']);
      });
    }

    test('when every mirror has the wrong size the download fails; the partial is kept for a retry', () async {
      server.dropAfter['/a'] = 100 * 1024;
      final r = _recording(body, [server.url('/a'), server.url('/wrongfull')]);
      final m = manager();
      server.onRequest = (path) {
        if (path == '/a' && server.ranges.length > 1) server.dropAfter['/a'] = 0; // it stays down
      };
      await expectLater(m.download(r), throwsA(isA<DownloadException>().having((e) => e.error, 'error', DownloadError.network)));
      expect(await m.partFileFor(r).length(), 100 * 1024);
      expect((await m.partialOf(r))!.received, 100 * 1024);
    });
  });

  test('a hash mismatch twice: one fresh download on the next mirror, then «verification»', () async {
    server.corruptLeft = 2;
    final r = _recording(body, [server.url('/corrupt'), server.url('/corrupt')]);
    final m = manager();
    final seen = <DownloadProgress>[];
    await expectLater(
      m.download(r, onProgress: seen.add),
      throwsA(isA<DownloadException>().having((e) => e.error, 'error', DownloadError.verification)),
    );
    expect(server.ranges, ['/corrupt 0', '/corrupt 0']); // the second from nothing
    expect((seen.last.phase, seen.last.error), (DownloadPhase.failed, DownloadError.verification));
    expect(m.partFileFor(r).existsSync(), isFalse); // nothing wrong is kept
    expect(await m.isDownloaded(r), isFalse);
    // «إعادة المحاولة» starts clean and succeeds.
    expect(await (await m.download(r)).readAsBytes(), body);
  });

  group('the disk fills while writing', () {
    test('ENOSPC is «noSpace», not «network»; no other mirror is tried; the bytes stay', () async {
      final transfer = _InstantTransfer(body)
        ..failWith = const FileSystemException('write failed', '', OSError('No space left on device', 28));
      final r = _recording(body, [server.url('/ok'), server.url('/ok')]);
      final m = manager(transfer: transfer);
      final seen = <DownloadProgress>[];
      await expectLater(
        m.download(r, onProgress: seen.add),
        throwsA(isA<DownloadException>().having((e) => e.error, 'error', DownloadError.noSpace)),
      );
      expect(transfer.fetches, 1);
      expect((seen.last.phase, seen.last.error), (DownloadPhase.failed, DownloadError.noSpace));
      expect((await m.partialOf(r))!.received, 1000);
    });

    test('a write error with too little space left is «noSpace» too, whatever its code', () async {
      final transfer = _InstantTransfer(body)..failWith = const FileSystemException('write failed');
      var free = body.length + kFreeSpaceMargin; // enough at the start
      final m = DownloadManager(
          supportDir: dir, freeBytes: () async => free, onUnmeteredNetwork: () async => true, retryDelay: Duration.zero, transfer: transfer);
      transfer.listening.future.ignore();
      final r = _recording(body, [server.url('/ok')]);
      final run = m.download(r);
      free = 10; // filled up by something else meanwhile
      await expectLater(run, throwsA(isA<DownloadException>().having((e) => e.error, 'error', DownloadError.noSpace)));
    });

    test('a write error with space left counts against the mirror: the next one is tried', () async {
      final transfer = _InstantTransfer(body)..failWith = const FileSystemException('write failed');
      final r = _recording(body, [server.url('/ok'), server.url('/ok')]);
      final file = await manager(transfer: transfer).download(r);
      expect(await file.readAsBytes(), body);
      expect(transfer.fetches, 2);
    });
  });

  test('no network: it waits, saying so, and goes on by itself when the network is back', () async {
    var checks = 0;
    final r = _recording(body, [server.url('/ok')]);
    final phases = <DownloadPhase>[];
    final file = await manager(online: () async => ++checks > 3).download(r, onProgress: (p) => phases.add(p.phase));
    expect(await file.readAsBytes(), body);
    expect(phases.where((p) => p == DownloadPhase.waitingForNetwork), hasLength(3));
    expect(phases.last, DownloadPhase.done);
    expect(server.ranges, ['/ok 0']); // no request while offline
  });

  test('the network drops in the middle: no round is spent; it resumes where it stopped', () async {
    var online = true;
    server.dropAfter['/a'] = 100 * 1024;
    server.onRequest = (path) {
      if (server.ranges.length == 1) online = false; // gone during the first request
    };
    var checks = 0;
    final r = _recording(body, [server.url('/a')]);
    final m = DownloadManager(
      supportDir: dir,
      freeBytes: () async => null,
      onUnmeteredNetwork: () async => true,
      online: () async => online || ++checks > 2,
      rounds: 1, // one round only: waiting for the network must not use it up
      retryDelay: Duration.zero,
      networkPoll: Duration.zero,
    );
    final phases = <DownloadPhase>[];
    final file = await m.download(r, onProgress: (p) => phases.add(p.phase));
    expect(await file.readAsBytes(), body);
    expect(phases, contains(DownloadPhase.waitingForNetwork));
    expect(server.ranges, ['/a 0', '/a ${100 * 1024}']);
  });

  test('waiting for Wi-Fi: «نزّل عبر البيانات» lets this one download go on over mobile data', () async {
    final transfer = _InstantTransfer(body);
    final r = _recording(body, [server.url('/ok')]);
    final control = DownloadCancel();
    final waiting = Completer<void>();
    final run = manager(wifi: () async => false, transfer: transfer).download(r, cancel: control, onProgress: (p) {
      if (p.phase == DownloadPhase.waitingForWifi && !waiting.isCompleted) waiting.complete();
    });
    await waiting.future;
    expect(transfer.fetches, 0);
    control.allowMetered();
    expect(await (await run).readAsBytes(), body);
    expect(transfer.wifiOnly, isFalse); // the transfer itself is told it may use any network
  });

  group('a verified file whose hash left the snapshot (after an app update)', () {
    test('another size: it needs an update, is not «on the device», and a download replaces it', () async {
      final m = manager();
      await m.download(_recording(body, [server.url('/ok')]));
      final newer = Uint8List.fromList([...body, 1, 2, 3]);
      final updated = _recording(newer, const []);
      expect((await m.isDownloaded(updated), await m.needsUpdate(updated)), (false, true));
      expect(await m.needsUpdate(_recording(body, const [])), isFalse); // the one it was verified for
      await m.delete(updated);
      expect((m.fileFor(updated).existsSync(), await m.needsUpdate(updated)), (false, false));
    });

    test('the same size, another hash: still not played', () async {
      final m = manager();
      await m.download(_recording(body, [server.url('/ok')]));
      final other = Uint8List.fromList(body)..[5] ^= 0xFF;
      final updated = _recording(other, const []);
      expect((await m.isDownloaded(updated), await m.needsUpdate(updated)), (false, true));
    });

    test('downloading the new one removes the old file first', () async {
      final m = manager();
      await m.download(_recording(body, [server.url('/ok')]));
      final other = Uint8List.fromList(body)..[5] ^= 0xFF;
      final second = _Server(other);
      await second.start();
      addTearDown(second.close);
      final updated = _recording(other, [second.url('/ok')]);
      final file = await m.download(updated);
      expect(await file.readAsBytes(), other);
      expect((await m.isDownloaded(updated), await m.needsUpdate(updated)), (true, false));
    });

    test('a file from before the markers, of the right size, is taken as verified and marked', () async {
      final m = manager();
      final r = _recording(body, const []);
      await m.fileFor(r).create(recursive: true);
      await m.fileFor(r).writeAsBytes(body);
      expect((await m.isDownloaded(r), await m.needsUpdate(r)), (true, false));
      await m.adoptVerified(r);
      final other = Uint8List.fromList(body)..[5] ^= 0xFF;
      expect(await m.needsUpdate(_recording(other, const [])), isTrue); // from now on a new hash is seen
    });
  });

  test('a server that ignores Range sends the whole file again: started over, still right', () async {
    await File('${manager().fileFor(_recording(body, [])).path}.part')
        .create(recursive: true)
        .then((f) => f.writeAsBytes(body.sublist(0, 1000)));
    final r = _recording(body, [server.url('/norange')]);
    final file = await manager().download(r);
    expect(await file.readAsBytes(), body);
  });

  test('a corrupted byte fails verification; the retry from nothing succeeds', () async {
    final r = _recording(body, [server.url('/corrupt')]);
    final phases = <DownloadPhase>[];
    final file = await manager().download(r, onProgress: (p) => phases.add(p.phase));
    expect(await file.readAsBytes(), body);
    expect(phases.where((p) => p == DownloadPhase.verifying), hasLength(2));
    expect(server.ranges, ['/corrupt 0', '/corrupt 0']);
  });

  test('not enough free space (file + 50 MB): refused before any request', () async {
    final r = _recording(body, [server.url('/ok')]);
    await expectLater(
      manager(free: body.length + kFreeSpaceMargin - 1).download(r),
      throwsA(isA<DownloadException>().having((e) => e.error, 'error', DownloadError.noSpace)),
    );
    expect(server.ranges, isEmpty);
  });

  test('Wi-Fi only: waits off Wi-Fi, then downloads', () async {
    var checks = 0;
    final r = _recording(body, [server.url('/ok')]);
    final phases = <DownloadPhase>[];
    final file = await manager(wifi: () async => ++checks > 2)
        .download(r, wifiPoll: Duration.zero, onProgress: (p) => phases.add(p.phase));
    expect(await file.readAsBytes(), body);
    expect(phases.first, DownloadPhase.waitingForWifi);
    expect(server.ranges, hasLength(1));
  });

  test('no hosting yet: no URLs is an error, not a hang', () async {
    await expectLater(
      manager().download(_recording(body, [])),
      throwsA(isA<DownloadException>().having((e) => e.error, 'error', DownloadError.noUrls)),
    );
  });

  group('recover and transfers', () {
    DownloadManager with_(Transfer t) => DownloadManager(
          supportDir: dir,
          freeBytes: () async => null,
          onUnmeteredNetwork: () async => true,
          transfer: t,
        );

    test('a complete, correct part file is verified and moved into place', () async {
      final r = _recording(body, [server.url('/ok')]);
      final m = manager();
      await (m.partFileFor(r)..parent.createSync(recursive: true)).writeAsBytes(body);
      expect(await m.recover(r), isTrue);
      expect(await m.isDownloaded(r), isTrue);
      expect(m.partFileFor(r).existsSync(), isFalse);
    });

    test('a corrupted part file is discarded; an incomplete one is kept for resuming', () async {
      final r = _recording(body, [server.url('/ok')]);
      final m = manager();
      await (m.partFileFor(r)..parent.createSync(recursive: true)).writeAsBytes(Uint8List.fromList(body)..[10] ^= 0xFF);
      expect(await m.recover(r), isFalse);
      expect(m.partFileFor(r).existsSync(), isFalse);

      await (m.partFileFor(r)..parent.createSync(recursive: true)).writeAsBytes(body.sublist(0, 1000));
      expect(await m.recover(r), isFalse);
      expect(m.partFileFor(r).lengthSync(), 1000);
      expect(await m.isDownloaded(r), isFalse);
    });

    test('two recover() calls at once rename once and neither throws (F-34)', () async {
      final r = _recording(body, [server.url('/ok')]);
      final m = manager();
      await (m.partFileFor(r)..parent.createSync(recursive: true)).writeAsBytes(body);
      // refresh() at launch and backgroundFinished() can both get here.
      final results = await Future.wait([m.recover(r), m.recover(r)]);
      expect(results, [isTrue, isTrue]);
      expect(await m.isDownloaded(r), isTrue);
      expect(m.partFileFor(r).existsSync(), isFalse);
    });

    test('any Transfer plugs in: its bytes are verified like the HTTP ones', () async {
      final r = _recording(body, ['https://mirror.invalid/a.mp3']);
      final file = await with_(_InstantTransfer(body)).download(r);
      expect(await file.readAsBytes(), body);

      final bad = _recording(body, ['https://mirror.invalid/a.mp3']);
      await with_(_InstantTransfer(body)).delete(bad);
      final corrupted = Uint8List.fromList(body)..[0] ^= 1;
      await expectLater(with_(_InstantTransfer(corrupted)).download(bad),
          throwsA(isA<DownloadException>().having((e) => e.error, 'error', DownloadError.verification)));
    });

    test('a transfer that does not poll is stopped through the cancel call', () async {
      final r = _recording(body, ['https://mirror.invalid/a.mp3']);
      final cancel = DownloadCancel();
      final transfer = _InstantTransfer(body, hang: true);
      final done = with_(transfer).download(r, cancel: cancel);
      await transfer.listening.future; // the transfer is running, however long the manager took to reach it
      cancel.cancel();
      await expectLater(done, throwsA(isA<DownloadException>().having((e) => e.error, 'error', DownloadError.cancelled)));
    });

    test('a cancel or a pause before the transfer starts stops the download; no transfer is started', () async {
      final r = _recording(body, ['https://mirror.invalid/a.mp3']);
      for (final (stop, error) in [
        ((DownloadCancel c) => c.cancel(), DownloadError.cancelled),
        ((DownloadCancel c) => c.pause(), DownloadError.paused),
      ]) {
        final cancel = DownloadCancel();
        final transfer = _InstantTransfer(body, hang: true);
        final phases = <DownloadPhase>[];
        final done = with_(transfer).download(r, cancel: cancel, onProgress: (p) => phases.add(p.phase));
        stop(cancel); // the manager is still looking at the device: nothing listens yet
        await expectLater(done, throwsA(isA<DownloadException>().having((e) => e.error, 'error', error)));
        expect(transfer.fetches, 0);
        expect(phases, [error == DownloadError.paused ? DownloadPhase.paused : DownloadPhase.cancelled]);
        expect((await with_(transfer).partialOf(r))!.paused, error == DownloadError.paused);
      }
    });
  });
}

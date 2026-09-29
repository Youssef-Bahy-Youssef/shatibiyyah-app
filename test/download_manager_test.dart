// The recording downloader against a local HTTP server with fault injection
// (plan P5 acceptance: resume after a kill, next mirror on failure, a corrupted
// byte fails verification and the retry works, low disk, Wi-Fi only).
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/data/recording_repository.dart';
import 'package:shatibiyyah/services/download_manager.dart';

/// Serves [body] at several paths, each with its own misbehaviour.
class _Server {
  final Uint8List body;
  late final HttpServer _server;
  final ranges = <String>[]; // "path start" per request
  int corruptLeft = 1; // /corrupt flips a byte this many times
  final dropAfter = <String, int>{}; // path -> close the connection after n bytes

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
    final res = req.response;
    if (path == '/fail') {
      res.statusCode = 500;
      await res.close();
      return;
    }
    var from = start;
    if (path == '/norange') from = 0;
    res.statusCode = from > 0 ? HttpStatus.partialContent : HttpStatus.ok;
    res.contentLength = body.length - from;
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

  DownloadManager manager({int? free, Future<bool> Function()? wifi}) => DownloadManager(
        supportDir: dir,
        freeBytes: () async => free,
        onUnmeteredNetwork: wifi ?? () async => true,
        retryDelay: Duration.zero,
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
}

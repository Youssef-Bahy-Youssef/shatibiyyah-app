// The Android transfer (background_downloader) under the download manager, with a
// fake FileDownloader (plan item 1.2, ADR 0007, F-30): «إيقاف مؤقت» pauses the task
// and «متابعة» resumes it from the bytes kept, never cancelling it; a partial is
// kept only for the delivery file it was started for and only when the server's
// total is that file's size.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatibiyyah/data/recording_repository.dart';
import 'package:shatibiyyah/services/background_transfer.dart';
import 'package:shatibiyyah/services/download_manager.dart';

/// Stands in for background_downloader: keeps tasks, records every call, and lets
/// the test play the platform's part (progress, completion).
class _FakeDownloader implements FileDownloader {
  final calls = <String>[];
  final active = <String, DownloadTask>{};
  final paused = <String, DownloadTask>{};
  final received = <String, int>{}; // bytes the task holds (its temp file)
  late void Function(TaskStatusUpdate) _status;
  late void Function(TaskProgressUpdate) _progress;

  /// Runs while a task is being queued, before the platform knows the task.
  void Function()? whileQueueing;

  @override
  FileDownloader registerCallbacks({
    String group = 'default',
    TaskStatusCallback? taskStatusCallback,
    TaskProgressCallback? taskProgressCallback,
    TaskNotificationTapCallback? taskNotificationTapCallback,
  }) {
    _status = taskStatusCallback!;
    _progress = taskProgressCallback!;
    return this;
  }

  @override
  Future<bool> enqueue(Task task) async {
    whileQueueing?.call();
    calls.add('enqueue ${(task as DownloadTask).url}');
    active[task.taskId] = task;
    received[task.taskId] = 0;
    return true;
  }

  @override
  Future<Task?> taskForId(String taskId) async => active[taskId] ?? paused[taskId];

  @override
  Future<bool> pause(DownloadTask task) async {
    calls.add('pause');
    final t = active.remove(task.taskId);
    if (t == null) return false;
    paused[t.taskId] = t;
    scheduleMicrotask(() => _status(TaskStatusUpdate(t, TaskStatus.paused)));
    return true;
  }

  @override
  Future<bool> resume(DownloadTask task) async {
    calls.add('resume');
    final t = paused.remove(task.taskId);
    if (t == null) return false;
    active[t.taskId] = t;
    return true;
  }

  @override
  Future<bool> cancelTaskWithId(String taskId) async {
    calls.add('cancel');
    final t = active.remove(taskId) ?? paused.remove(taskId);
    received.remove(taskId);
    if (t != null) scheduleMicrotask(() => _status(TaskStatusUpdate(t, TaskStatus.canceled)));
    return t != null;
  }

  DownloadTask get running => active.values.single;

  /// The platform reports [bytes] of [total] received (the 206 total is [total]).
  void progress(int bytes, int total) {
    final t = running;
    received[t.taskId] = bytes;
    _progress(TaskProgressUpdate(t, bytes / total, total));
  }

  /// The task finishes: its bytes appear at the task's path.
  Future<void> complete(Uint8List body) async {
    final t = running;
    await File('/${t.directory}/${t.filename}').writeAsBytes(body); // BaseDirectory.root: an absolute path
    active.remove(t.taskId);
    _status(TaskStatusUpdate(t, TaskStatus.complete));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Recording _recording(Uint8List body, List<String> urls) => Recording(
      'recording:test', 'test-reciter', 'reciter:test', 'قارئ', 'تلاوة', null, true, 60000, body.length,
      sha256.convert(body).toString(), 'verified', null, null, null,
      DeliveryFile(sha256.convert(body).toString(), body.length, 60000, 'audio/mpeg', urls),
    );

void main() {
  late Directory dir;
  late Uint8List body;
  late _FakeDownloader fake;
  late DownloadManager manager;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('background_transfer');
    body = Uint8List.fromList(List.generate(200 * 1000, (i) => Random(3).nextInt(256) ^ (i & 0xFF)));
    fake = _FakeDownloader();
    manager = DownloadManager(
      supportDir: dir,
      freeBytes: () async => null,
      onUnmeteredNetwork: () async => true,
      retryDelay: Duration.zero,
      transfer: BackgroundTransfer.withDownloader(fake,
          split: (path) async => (BaseDirectory.root, File(path).parent.path, File(path).uri.pathSegments.last)),
    );
  });

  tearDown(() => dir.delete(recursive: true));

  /// Lets the manager reach the transfer (file I/O, the fake's microtasks) until [ok].
  Future<void> until(bool Function() ok) async {
    for (var i = 0; i < 500 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(ok(), isTrue, reason: 'calls so far: ${fake.calls}');
  }

  Future<void> settle() => until(() => fake.active.isNotEmpty);

  test('pause, then resume: pause and resume are called, never cancel; bytes continue', () async {
    final r = _recording(body, ['https://a.invalid/x.mp3', 'https://b.invalid/x.mp3']);
    final control = DownloadCancel();
    final seen = <DownloadProgress>[];
    final first = manager.download(r, cancel: control, onProgress: seen.add);
    await settle();
    fake.progress(120000, body.length); // 60 %
    control.pause();
    await expectLater(first, throwsA(isA<DownloadException>().having((e) => e.error, 'error', DownloadError.paused)));
    expect(seen.last.phase, DownloadPhase.paused);
    expect(seen.last.fraction, closeTo(0.6, 0.001));

    // What the reader sees after a relaunch: paused at 60 %, tied to this delivery file.
    final kept = (await manager.partialOf(r))!;
    expect((kept.received, kept.paused), (120000, true));
    final sidecar = jsonDecode(await File('${dir.path}/audio/test-reciter.part.json').readAsString()) as Map;
    expect(sidecar['delivery_sha256'], r.delivery!.sha256);

    final second = manager.download(r);
    await settle();
    await fake.complete(body);
    expect(await (await second).readAsBytes(), body);
    expect(fake.calls, ['enqueue https://a.invalid/x.mp3', 'pause', 'resume']);
    expect(await manager.partialOf(r), isNull);
  });

  test('a partial kept for an older delivery file is discarded, and the download starts over', () async {
    final r = _recording(body, ['https://a.invalid/x.mp3']);
    final control = DownloadCancel();
    final first = manager.download(r, cancel: control);
    await settle();
    fake.progress(50000, body.length);
    control.pause();
    await expectLater(first, throwsA(isA<DownloadException>()));

    // An app update ships a snapshot with a new delivery file under the same name.
    final newer = Uint8List.fromList(body)..[0] ^= 0xFF;
    final updated = _recording(newer, ['https://a.invalid/x.mp3']);
    expect(await manager.partialOf(updated), isNull);
    final second = manager.download(updated);
    await settle();
    expect(fake.calls, ['enqueue https://a.invalid/x.mp3', 'pause', 'cancel', 'enqueue https://a.invalid/x.mp3']);
    expect(fake.paused, isEmpty);
    await fake.complete(newer);
    expect(await (await second).readAsBytes(), newer);
  });

  test('a 206 total that is not delivery_bytes is discarded; the next mirror starts clean', () async {
    final r = _recording(body, ['https://a.invalid/x.mp3', 'https://b.invalid/x.mp3']);
    final done = manager.download(r);
    await settle();
    fake.progress(1000, body.length + 1); // this mirror serves another file
    await until(() => fake.calls.length == 3);
    expect(fake.calls, ['enqueue https://a.invalid/x.mp3', 'cancel', 'enqueue https://b.invalid/x.mp3']);
    fake.progress(1000, body.length);
    await fake.complete(body);
    expect(await (await done).readAsBytes(), body);
  });

  test('a cancel before the transfer starts: no task is queued', () async {
    final r = _recording(body, ['https://a.invalid/x.mp3']);
    final control = DownloadCancel();
    final done = manager.download(r, cancel: control);
    control.cancel(); // the manager is still looking at the device
    await expectLater(done, throwsA(isA<DownloadException>().having((e) => e.error, 'error', DownloadError.cancelled)));
    expect(fake.calls, isEmpty);
  });

  test('a cancel while the task is being queued: the task is cancelled once the platform has it', () async {
    final r = _recording(body, ['https://a.invalid/x.mp3']);
    final control = DownloadCancel();
    fake.whileQueueing = control.cancel; // this cancel call finds no task yet
    await expectLater(manager.download(r, cancel: control),
        throwsA(isA<DownloadException>().having((e) => e.error, 'error', DownloadError.cancelled)));
    expect(fake.calls, ['cancel', 'enqueue https://a.invalid/x.mp3', 'cancel']);
    expect(fake.active, isEmpty);
  });

  test('delete removes a paused partial: the task, its temp file and the sidecar', () async {
    final r = _recording(body, ['https://a.invalid/x.mp3']);
    final control = DownloadCancel();
    final first = manager.download(r, cancel: control);
    await settle();
    fake.progress(90000, body.length);
    control.pause();
    await expectLater(first, throwsA(isA<DownloadException>()));

    await manager.delete(r);
    expect(fake.calls.last, 'cancel'); // background_downloader deletes a paused task's temp file on cancel
    expect(fake.paused, isEmpty);
    expect(await manager.partialOf(r), isNull);
    expect(File('${dir.path}/audio/test-reciter.part.json').existsSync(), isFalse);
  });
}

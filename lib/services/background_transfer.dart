// lib/services/background_transfer.dart — the recording's bytes over
// background_downloader (Android WorkManager): the download carries on when the
// app is left or closed. With allowPause a task that meets Android's 9-minute
// limit pauses and resumes by itself (the mirrors serve Range requests), so no
// foreground service is needed. The file appears at the part path only when
// complete; DownloadManager verifies it (and DownloadManager.recover does so at
// the next launch when it finished while the app was closed).
//
// «إيقاف مؤقت» pauses the task, and background_downloader keeps its temporary
// file and resume data; the next fetch resumes it (ADR 0007, F-30). Cancelling a
// task deletes them, so only a cancel or a delete does.
import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import 'download_manager.dart';

typedef SplitPath = Future<(BaseDirectory, String, String)> Function(String filePath);

class BackgroundTransfer extends Transfer {
  static const String group = 'recordings';

  final FileDownloader _downloader;
  final SplitPath _split;
  final _waiting = <String, Completer<TaskStatusUpdate>>{};
  final _progress = <String, void Function(TaskProgressUpdate)>{};

  /// A task finished with nobody waiting for it (it ran while the app was closed).
  void Function()? onUnattendedComplete;

  BackgroundTransfer._(this._downloader, this._split);

  /// Registers the callbacks, then picks up what happened while the app was away
  /// and reschedules tasks the system killed.
  static Future<BackgroundTransfer> start() async {
    final transfer = BackgroundTransfer.withDownloader(FileDownloader());
    await transfer._downloader.start();
    return transfer;
  }

  /// Over [downloader] (a fake in tests), with its callbacks registered.
  @visibleForTesting
  factory BackgroundTransfer.withDownloader(FileDownloader downloader, {SplitPath? split}) {
    final transfer = BackgroundTransfer._(downloader, split ?? ((path) => Task.split(filePath: path)));
    downloader.registerCallbacks(
      group: group,
      taskStatusCallback: transfer._onStatus,
      taskProgressCallback: transfer._onProgress,
    );
    return transfer;
  }

  static String taskIdFor(File part) => 'recording:${p.basename(part.path)}';

  /// Whether a transfer into [part] is queued or running (e.g. since before a relaunch).
  Future<bool> isActive(File part) async => await _downloader.taskForId(taskIdFor(part)) != null;

  void _onStatus(TaskStatusUpdate u) {
    if (!u.status.isFinalState && u.status != TaskStatus.paused) return;
    final waiter = _waiting.remove(u.task.taskId);
    if (waiter != null) {
      waiter.complete(u);
    } else if (u.status == TaskStatus.complete) {
      onUnattendedComplete?.call();
    }
  }

  void _onProgress(TaskProgressUpdate u) {
    if (u.progress >= 0 && u.progress <= 1) _progress[u.task.taskId]?.call(u);
  }

  /// A paused or running task for [part] is cancelled: background_downloader then
  /// deletes its temporary file and resume data.
  @override
  Future<void> discard(File part) async {
    final taskId = taskIdFor(part);
    if (await _downloader.taskForId(taskId) != null) await _downloader.cancelTaskWithId(taskId);
  }

  @override
  Future<void> fetch(
    Uri url,
    File part,
    int total,
    void Function(int) progress,
    DownloadCancel? cancel, {
    required bool wifiOnly,
  }) async {
    final taskId = taskIdFor(part);
    final done = _waiting[taskId] ??= Completer<TaskStatusUpdate>();
    int? served;
    _progress[taskId] = (u) {
      // The total of a resumed task is the 206 total: it must be the delivery size.
      if (u.expectedFileSize > 0 && u.expectedFileSize != total && served == null) {
        served = u.expectedFileSize;
        _downloader.cancelTaskWithId(taskId);
        return;
      }
      progress((u.progress * total).round());
    };
    cancel?.onCancel(() => _downloader.cancelTaskWithId(taskId));
    cancel?.onPause(() async {
      final task = await _downloader.taskForId(taskId);
      if (task is DownloadTask) await _downloader.pause(task);
    });
    try {
      final existing = await _downloader.taskForId(taskId);
      if (existing is DownloadTask) {
        // A paused task resumes from its temporary file. A task still running from
        // before (the app was closed and reopened) has nothing to resume (false):
        // it is waited for, not started twice.
        await _downloader.resume(existing);
      } else if (existing == null) {
        final (base, directory, filename) = await _split(part.path);
        final queued = await _downloader.enqueue(
          DownloadTask(
            taskId: taskId,
            url: url.toString(),
            filename: filename,
            directory: directory,
            baseDirectory: base,
            group: group,
            updates: Updates.statusAndProgress,
            requiresWiFi: wifiOnly,
            retries: 3,
            allowPause: true,
            displayName: 'تنزيل التلاوة',
          ),
        );
        if (!queued) throw HttpException('not queued', uri: url);
      }
      // Cancelled while the task was being queued: the listener's call found no task.
      if (cancel?.cancelled ?? false) {
        await _downloader.cancelTaskWithId(taskId);
      } else if (cancel?.paused ?? false) {
        // «إيقاف مؤقت» pressed while the task was being queued.
        final task = await _downloader.taskForId(taskId);
        if (task is DownloadTask) await _downloader.pause(task);
      }
      final update = await done.future;
      if (served != null) throw TransferSizeMismatch(served!);
      switch (update.status) {
        case TaskStatus.complete:
          return;
        case TaskStatus.paused:
        case TaskStatus.canceled when cancel?.stopped ?? false:
          throw const TransferCancelled();
        default:
          throw HttpException('${update.status.name} ${update.responseStatusCode ?? ''}'.trim(), uri: url);
      }
    } finally {
      _waiting.remove(taskId);
      _progress.remove(taskId);
    }
  }
}

// lib/services/background_transfer.dart — the recording's bytes over
// background_downloader (Android WorkManager): the download carries on when the
// app is left or closed. With allowPause a task that meets Android's 9-minute
// limit pauses and resumes by itself (the mirrors serve Range requests), so no
// foreground service is needed. The file appears at the part path only when
// complete; DownloadManager verifies it (and DownloadManager.recover does so at
// the next launch when it finished while the app was closed).
import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:path/path.dart' as p;

import 'download_manager.dart';

class BackgroundTransfer implements Transfer {
  static const String group = 'recordings';

  final FileDownloader _downloader;
  final _waiting = <String, Completer<TaskStatusUpdate>>{};
  final _progress = <String, void Function(double)>{};

  /// A task finished with nobody waiting for it (it ran while the app was closed).
  void Function()? onUnattendedComplete;

  BackgroundTransfer._(this._downloader);

  /// Registers the callbacks, then picks up what happened while the app was away
  /// and reschedules tasks the system killed.
  static Future<BackgroundTransfer> start() async {
    final transfer = BackgroundTransfer._(FileDownloader());
    transfer._downloader.registerCallbacks(
      group: group,
      taskStatusCallback: transfer._onStatus,
      taskProgressCallback: transfer._onProgress,
    );
    await transfer._downloader.start();
    return transfer;
  }

  static String taskIdFor(File part) => 'recording:${p.basename(part.path)}';

  /// Whether a transfer into [part] is queued or running (e.g. since before a relaunch).
  Future<bool> isActive(File part) async => await _downloader.taskForId(taskIdFor(part)) != null;

  void _onStatus(TaskStatusUpdate u) {
    if (!u.status.isFinalState) return;
    final waiter = _waiting.remove(u.task.taskId);
    if (waiter != null) {
      waiter.complete(u);
    } else if (u.status == TaskStatus.complete) {
      onUnattendedComplete?.call();
    }
  }

  void _onProgress(TaskProgressUpdate u) {
    if (u.progress >= 0 && u.progress <= 1) _progress[u.task.taskId]?.call(u.progress);
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
    _progress[taskId] = (f) => progress((f * total).round());
    cancel?.onCancel(() => _downloader.cancelTaskWithId(taskId));
    try {
      // A task still running from before (the app was closed and reopened) is
      // waited for, not started twice.
      if (await _downloader.taskForId(taskId) == null) {
        final (base, directory, filename) = await Task.split(filePath: part.path);
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
      final update = await done.future;
      switch (update.status) {
        case TaskStatus.complete:
          return;
        case TaskStatus.canceled when cancel?.cancelled ?? false:
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

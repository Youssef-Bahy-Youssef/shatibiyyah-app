// lib/services/device_storage.dart — the two questions the recording downloader asks
// the device, answered by MainActivity on Android ("taysir/device" channel).
// Elsewhere (iOS not yet in scope, tests) the answers are "unknown" and "yes".
import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('taysir/device');

/// Free bytes on the volume holding the app's files, or null when unknown.
Future<int?> deviceFreeBytes() async {
  try {
    return await _channel.invokeMethod<int>('freeBytes');
  } on MissingPluginException {
    return null;
  }
}

/// Whether the device is on Wi-Fi or Ethernet now (true when the platform cannot say).
Future<bool> deviceOnUnmeteredNetwork() async {
  try {
    return await _channel.invokeMethod<bool>('unmetered') ?? true;
  } on MissingPluginException {
    return true;
  }
}

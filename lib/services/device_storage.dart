// lib/services/device_storage.dart — what the app asks the device, answered by
// MainActivity on Android ("taysir/device" channel): the recording downloader's
// two questions (free space, unmetered network) and the system's «save as» and
// «open» document pickers, for backups and for a share card's image. Elsewhere (iOS not yet in scope, tests)
// the answers are "unknown" and "yes", and the pickers are unsupported.
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

/// Why a document could not be saved or read.
class DocumentError implements Exception {
  final String code; // 'unsupported', 'too_large', 'io', 'busy'
  const DocumentError(this.code);
}

/// Lets the user save [text] as a file named [name] where they choose (the
/// system's «save as»). Null when they cancel.
Future<String?> saveDocument(String name, String text) async {
  try {
    return await _channel.invokeMethod<String>('saveDocument', {'name': name, 'text': text});
  } on MissingPluginException {
    throw const DocumentError('unsupported');
  } on PlatformException catch (e) {
    throw DocumentError(e.code);
  }
}

/// Lets the user pick a file and returns its text. Null when they cancel.
Future<String?> openDocument() async {
  try {
    return await _channel.invokeMethod<String>('openDocument');
  } on MissingPluginException {
    throw const DocumentError('unsupported');
  } on PlatformException catch (e) {
    throw DocumentError(e.code);
  }
}

/// Lets the user save the PNG [bytes] as [name] where they choose (the system's
/// «save as»). False when they cancel.
Future<bool> saveImage(String name, Uint8List bytes) async {
  try {
    return await _channel.invokeMethod<String>('saveImage', {'name': name, 'bytes': bytes}) != null;
  } on MissingPluginException {
    throw const DocumentError('unsupported');
  } on PlatformException catch (e) {
    throw DocumentError(e.code);
  }
}

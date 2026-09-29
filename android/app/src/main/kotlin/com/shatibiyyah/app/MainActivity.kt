package com.shatibiyyah.app

import android.content.Context
import android.net.ConnectivityManager
import android.os.StatFs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// just_audio_background / audio_service requires the host Activity to extend
// AudioServiceActivity so the background media service binds to the correct FlutterEngine.
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // What the recording downloader asks the device (lib/services/device_storage.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "taysir/device").setMethodCallHandler { call, result ->
            when (call.method) {
                // Free bytes on the volume holding the app's files.
                "freeBytes" -> result.success(StatFs(filesDir.path).availableBytes)
                // Wi-Fi or Ethernet (an unmetered network), for «Wi-Fi only».
                "unmetered" -> {
                    val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                    result.success(cm.activeNetwork != null && !cm.isActiveNetworkMetered)
                }
                else -> result.notImplemented()
            }
        }
    }
}

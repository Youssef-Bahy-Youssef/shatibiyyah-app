package com.shatibiyyah.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.os.StatFs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// audio_service (the lock screen) requires the host Activity to extend
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
                // «نسخ احتياطي»: the system's «save as» and «open» pickers, so a backup is a
                // file wherever the user puts it (Downloads, Drive…), with no storage permission.
                "saveDocument" -> startDocument(result, call.argument<String>("text") ?: "") {
                    Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/json"
                        putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
                    }
                }
                "openDocument" -> startDocument(result, null) {
                    Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*" // some providers label .json as text/plain or octet-stream
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private var pending: MethodChannel.Result? = null
    private var pendingText: String? = null

    private fun startDocument(result: MethodChannel.Result, text: String?, intent: () -> Intent) {
        if (pending != null) {
            result.error("busy", "a picker is already open", null)
            return
        }
        pending = result
        pendingText = text
        startActivityForResult(intent(), REQUEST_DOCUMENT)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_DOCUMENT) return
        val result = pending ?: return
        val text = pendingText
        pending = null
        pendingText = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null) // cancelled
            return
        }
        try {
            if (text != null) {
                contentResolver.openOutputStream(uri, "wt")!!.use { it.write(text.toByteArray(Charsets.UTF_8)) }
                result.success(uri.lastPathSegment ?: "")
            } else {
                val bytes = contentResolver.openInputStream(uri)!!.use { it.readBytes() }
                if (bytes.size > MAX_DOCUMENT_BYTES) {
                    result.error("too_large", "file too large", null)
                } else {
                    result.success(String(bytes, Charsets.UTF_8))
                }
            }
        } catch (e: Exception) {
            result.error("io", e.message, null)
        }
    }

    companion object {
        private const val REQUEST_DOCUMENT = 4201
        private const val MAX_DOCUMENT_BYTES = 20 * 1024 * 1024
    }
}

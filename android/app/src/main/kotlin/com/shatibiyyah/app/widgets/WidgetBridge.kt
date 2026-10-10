package com.shatibiyyah.app.widgets

import android.content.Context
import android.content.Intent
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * The app's side of the widgets: the `taysir/widgets` channel of lib/app/widgets.dart.
 *
 * The app publishes the reader's state here; the widgets' taps go back as requests. While the app
 * is not running a request is kept in [WidgetStore], and the app takes it when it starts.
 */
object WidgetBridge {
    const val ACTION_OPEN = "com.shatibiyyah.app.widget.OPEN"

    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var taken = false // the app has asked for what was kept: from here on it is listening
    private var onPublished: (() -> Unit)? = null

    /** Joins [engine], the one engine the app and its audio service share. Safe to call again. */
    fun attach(context: Context, engine: FlutterEngine) {
        if (this.engine === engine) return
        val app = context.applicationContext
        this.engine = engine
        taken = false
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "taysir/widgets").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "publish" -> {
                        WidgetStore.setResume(app, call.arguments as String)
                        ResumeWidget.redrawAll(app)
                        DayWidget.redrawAll(app) // it draws again only if its theme, ink or rubric changed
                        onPublished?.invoke()
                        onPublished = null
                        result.success(null)
                    }
                    "takePending" -> {
                        taken = true
                        result.success(WidgetStore.takePending(app))
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** Whether the app is running and listening: its engine is alive and it has taken what was kept. */
    internal fun ready(): Boolean {
        val e = engine ?: return false
        return taken && FlutterEngineCache.getInstance().get(AudioServicePlugin.getFlutterEngineId()) === e
    }

    /** Hands [request] to the app: now if it is listening, else when it next starts. */
    internal fun request(context: Context, request: Map<String, Any>) {
        if (ready()) channel?.invokeMethod("request", request) else WidgetStore.addPending(context, request)
    }

    /**
     * Starts the app with no screen, as its audio service does for a headset button: the same
     * engine an activity would join later. [then] runs once the app has published its state.
     */
    internal fun startWithoutScreen(context: Context, then: () -> Unit) {
        onPublished = then
        attach(context, AudioServicePlugin.getFlutterEngine(context.applicationContext))
    }

    /** A tap that opened the app (`taysir://widget/verse/N` or `…/downloads`), as a request; null for any other intent. */
    internal fun requestOf(intent: Intent?): Map<String, Any>? {
        if (intent?.action != ACTION_OPEN) return null
        val path = intent.data?.pathSegments ?: return null
        return when (path.firstOrNull()) {
            "verse" -> path.getOrNull(1)?.toIntOrNull()?.let { mapOf("do" to "verse", "verse" to it) }
            "downloads" -> mapOf("do" to "downloads")
            else -> null
        }
    }
}

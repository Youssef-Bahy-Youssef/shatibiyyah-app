package com.shatibiyyah.app.widgets

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * ▶ and ❚❚ on «تابع». Each says what it wants, so a button that is out of date cannot do the
 * opposite of what it shows.
 *
 * With the app running the widget shows the tap at once and the request goes to the reader, the
 * same way the lock screen's buttons do. With nothing running, ❚❚ has nothing to stop and only
 * corrects the picture; ▶ is kept for the app to take, and [WidgetStartService] starts the app
 * with no screen.
 */
class WidgetActions : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        val play = when (intent.action) {
            PLAY -> true
            PAUSE -> false
            else -> return
        }
        if (WidgetBridge.ready()) {
            WidgetStore.setPlaying(app, play)
            WidgetBridge.request(app, mapOf("do" to if (play) "play" else "pause"))
            ResumeWidget.redrawAll(app)
            return
        }
        if (!play) {
            WidgetStore.setPlaying(app, false)
            ResumeWidget.redrawAll(app)
            return
        }
        // Nothing is running. ▶ is kept for the app to take, and a service starts the app with no
        // screen (a broadcast cannot stay open that long). The widget shows ❚❚ meanwhile.
        if (WidgetStartService.starting) return
        WidgetStore.addPending(app, mapOf("do" to "play"))
        WidgetStore.setPlaying(app, true)
        try {
            WidgetStartService.start(app)
        } catch (_: Exception) {
            // The system refused to start it from here: nothing plays, and the widget says so.
            WidgetStore.takePending(app)
            WidgetStore.setPlaying(app, false)
        }
        ResumeWidget.redrawAll(app)
    }

    companion object {
        const val PLAY = "com.shatibiyyah.app.widget.PLAY"
        const val PAUSE = "com.shatibiyyah.app.widget.PAUSE"
    }
}

package com.shatibiyyah.app.widgets

import android.content.BroadcastReceiver
import java.util.concurrent.Executors

/**
 * The widgets' drawing, one at a time and off the main thread: the first drawing installs the
 * content and measures the poem. A broadcast that asked for it stays open until it is done.
 */
internal object WidgetWork {
    private val work = Executors.newSingleThreadExecutor()

    fun later(pending: BroadcastReceiver.PendingResult?, task: () -> Unit) {
        work.execute {
            try {
                task()
            } catch (_: Exception) {
            } finally {
                pending?.finish()
            }
        }
    }
}
